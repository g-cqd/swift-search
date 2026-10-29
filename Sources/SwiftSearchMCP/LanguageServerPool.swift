public import SwiftSearchLSP
internal import Synchronization

/// The sourcekit-lsp sessions of a long-running server, one per workspace, started on first use and kept until
/// ``shutdown()``.
///
/// Sessions run as children of ``run()``, which the server runs in its own task group: no session outlives the
/// server, and every one is shut down through sourcekit-lsp's `shutdown` and `exit`.
public final class LanguageServerPool: LanguageServerProvider {
    /// The most workspaces served at once; a request for another fails until the server restarts.
    public static let maximumWorkspaces = 4

    private enum Entry {
        case starting([CheckedContinuation<LanguageServerSession, any Error>])
        case ready(LanguageServerSession, stop: AsyncStream<Never>.Continuation)
    }

    private struct State {
        var entries: [String: Entry] = [:]
        var isShutDown = false
    }

    private let state = Mutex(State())
    private let starts: AsyncStream<String>
    private let startContinuation: AsyncStream<String>.Continuation
    private let executable: String?

    /// - Parameter executable: a sourcekit-lsp to run instead of the toolchain's.
    public init(executable: String? = nil) {
        (starts, startContinuation) = AsyncStream.makeStream()
        self.executable = executable
    }

    /// The session for `workspace`, starting sourcekit-lsp there the first time.
    /// - Throws: ``LanguageServerError`` when the server cannot start; an error past ``maximumWorkspaces`` or after
    ///   ``shutdown()``.
    public func session(for workspace: String) async throws -> LanguageServerSession {
        try await withCheckedThrowingContinuation { continuation in
            enum Next {
                case deliver(LanguageServerSession)
                case wait
                case start
                case refuse(String)
            }
            let next = state.withLock { state -> Next in
                if state.isShutDown { return .refuse("the server is shutting down") }
                switch state.entries[workspace] {
                case .ready(let session, _):
                    return .deliver(session)
                case .starting(let waiting):
                    state.entries[workspace] = .starting(waiting + [continuation])
                    return .wait
                case nil:
                    guard state.entries.count < Self.maximumWorkspaces else {
                        return .refuse("sourcekit-lsp already serves \(Self.maximumWorkspaces) workspaces")
                    }
                    state.entries[workspace] = .starting([continuation])
                    return .start
                }
            }
            switch next {
            case .deliver(let session): continuation.resume(returning: session)
            case .wait: break
            case .start: startContinuation.yield(workspace)
            case .refuse(let reason):
                continuation.resume(throwing: LanguageServerError.connectionClosed(reason: reason))
            }
        }
    }

    /// Runs each session asked for until ``shutdown()``, then waits for every one to stop.
    public func run() async {
        await withTaskGroup(of: Void.self) { group in
            for await workspace in starts {
                group.addTask { await self.serve(workspace) }
            }
        }
    }

    /// Stops accepting workspaces and shuts every session down; ``run()`` returns once they have stopped.
    public func shutdown() {
        let stops = state.withLock { state -> [AsyncStream<Never>.Continuation] in
            state.isShutDown = true
            return state.entries.values.compactMap {
                if case .ready(_, let stop) = $0 { return stop }
                return nil
            }
        }
        startContinuation.finish()
        for stop in stops { stop.finish() }
    }

    private func serve(_ workspace: String) async {
        do {
            try await SourceKitLSP.withSession(workspace: workspace, executable: executable) { session in
                let (stopped, stop) = AsyncStream<Never>.makeStream()
                let waiting = state.withLock { state -> [CheckedContinuation<LanguageServerSession, any Error>] in
                    guard case .starting(let waiting) = state.entries[workspace] else { return [] }
                    state.entries[workspace] = .ready(session, stop: stop)
                    if state.isShutDown { stop.finish() }
                    return waiting
                }
                for continuation in waiting { continuation.resume(returning: session) }
                // Until shutdown, or until the server exits on its own.
                await withTaskGroup(of: Void.self) { group in
                    group.addTask { for await _ in stopped {} }
                    group.addTask { await session.connection.waitUntilClosed() }
                    _ = await group.next()
                    group.cancelAll()
                    stop.finish()
                }
            }
            state.withLock { $0.entries[workspace] = nil }
        } catch {
            let waiting = state.withLock { state -> [CheckedContinuation<LanguageServerSession, any Error>] in
                defer { state.entries[workspace] = nil }
                if case .starting(let waiting) = state.entries[workspace] { return waiting }
                return []
            }
            for continuation in waiting { continuation.resume(throwing: error) }
        }
    }
}
