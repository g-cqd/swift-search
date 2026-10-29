public import AemiJSON
internal import Synchronization

/// Where a connection writes its messages: a child's standard input, or a test's buffer.
public protocol MessageSink: Sendable {
    /// Writes `bytes` whole, or throws.
    func write(_ bytes: [UInt8]) async throws
}

/// Why a request to the language server gave no result.
public enum LanguageServerError: Error, Sendable, Equatable, CustomStringConvertible {
    /// The server answered with a JSON-RPC error.
    case response(code: Int, message: String)
    /// No answer within the deadline.
    case timedOut(method: String, after: Duration)
    /// The server's output ended or broke before the answer.
    case connectionClosed(reason: String)
    /// No trusted sourcekit-lsp was found.
    case serverNotFound(String)
    /// The workspace root is not a directory.
    case invalidWorkspace(String)
    /// A file the request names could not be read.
    case unreadableFile(String)

    public var description: String {
        switch self {
        case .response(let code, let message): "sourcekit-lsp answered with error \(code): \(message)"
        case .timedOut(let method, let after): "sourcekit-lsp did not answer \(method) within \(after)"
        case .connectionClosed(let reason): "the connection to sourcekit-lsp closed: \(reason)"
        case .serverNotFound(let reason): "no sourcekit-lsp to run: \(reason)"
        case .invalidWorkspace(let path): "\(path) is not a directory"
        case .unreadableFile(let path): "\(path) could not be read"
        }
    }
}

/// JSON-RPC 2.0 over the base protocol's framing: requests matched to their responses by id, any number in flight.
///
/// Requests the server sends the client (`window/workDoneProgress/create`, `client/registerCapability`) are answered
/// with a null result so the server never waits on the client; notifications are dropped.
public final class LanguageServerConnection: Sendable {
    private enum Slot {
        /// Sent; nobody waits yet.
        case pending
        case waiting(CheckedContinuation<JSON, any Error>)
        case answered(Result<JSON, LanguageServerError>)
    }

    private struct State {
        var nextID = 1
        var slots: [Int: Slot] = [:]
        /// Set once the server's output ends: every later request fails at once.
        var closed: LanguageServerError?
        var closeWaiters: [Int: CheckedContinuation<Void, Never>] = [:]
        var nextWaiter = 0
    }

    private let sink: any MessageSink
    private let state = Mutex(State())

    public init(sink: any MessageSink) {
        self.sink = sink
    }

    // MARK: Sending

    /// Sends `method` with `params` and returns the response's `result`.
    ///
    /// - Throws: ``LanguageServerError`` for an error response, a closed connection or the deadline; a write
    ///   failure; `CancellationError` when the caller is cancelled. A late answer to an abandoned request is dropped.
    public func request(_ method: String, _ params: JSONValue, timeout: Duration = .seconds(120)) async throws -> JSON {
        let id = try state.withLock { state throws(LanguageServerError) -> Int in
            if let closed = state.closed { throw closed }
            let id = state.nextID
            state.nextID += 1
            state.slots[id] = .pending
            return id
        }
        do {
            try await sink.write(Self.message(id: .int(Int64(id)), method: method, params: params))
            return try await withThrowingTaskGroup(of: JSON.self) { group in
                group.addTask { try await self.answer(id) }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    throw LanguageServerError.timedOut(method: method, after: timeout)
                }
                defer { group.cancelAll() }
                guard let result = try await group.next() else { throw CancellationError() }
                return result
            }
        } catch {
            abandon(id)
            throw error
        }
    }

    /// Sends a notification: no id, no answer.
    public func notify(_ method: String, _ params: JSONValue) async throws {
        try await sink.write(Self.message(id: nil, method: method, params: params))
    }

    /// Waits for the answer to `id`, or for cancellation.
    private func answer(_ id: Int) async throws -> JSON {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<JSON, any Error>) in
                enum Next {
                    case wait
                    case deliver(Result<JSON, LanguageServerError>)
                    case abandoned
                }
                let next = state.withLock { state -> Next in
                    switch state.slots[id] {
                    case .pending:
                        state.slots[id] = .waiting(continuation)
                        return .wait
                    case .answered(let result):
                        state.slots[id] = nil
                        return .deliver(result)
                    case .waiting, nil:
                        return .abandoned
                    }
                }
                switch next {
                case .wait: break
                case .deliver(let result): continuation.resume(with: result)
                case .abandoned: continuation.resume(throwing: CancellationError())
                }
            }
        } onCancel: {
            abandon(id)
        }
    }

    /// Forgets `id`; a waiter is resumed with `CancellationError`.
    private func abandon(_ id: Int) {
        let waiter = state.withLock { state -> CheckedContinuation<JSON, any Error>? in
            defer { state.slots[id] = nil }
            if case .waiting(let continuation) = state.slots[id] { return continuation }
            return nil
        }
        waiter?.resume(throwing: CancellationError())
    }

    // MARK: Receiving

    /// Reads the server's output until it ends, delivering each response to its request.
    ///
    /// When the output ends or is not framed, every request in flight fails with
    /// ``LanguageServerError/connectionClosed(reason:)``, and so does every later one.
    public func run(reading chunks: some AsyncSequence<[UInt8], any Error>) async {
        var decoder = LSPFrameDecoder()
        var reason = "the server's output ended"
        do {
            for try await chunk in chunks {
                for body in try decoder.append(chunk) { await receive(body) }
            }
        } catch {
            reason = String(describing: error)
        }
        close(reason: reason)
    }

    /// Delivers one message.
    func receive(_ body: [UInt8]) async {
        guard let document = try? AemiJSON.parse(body) else { return }
        let message = document.root
        let id = message["id"]
        if message["method"].exists {
            // A request from the server: answer it so the server does not wait on us. A notification needs nothing.
            if id.exists, let rawID = try? id.encodedBytes() {
                try? await sink.write(Self.nullResult(rawID: rawID))
            }
            return
        }
        guard let number = id.int else { return }
        let result: Result<JSON, LanguageServerError>
        let error = message["error"]
        if error.exists {
            result = .failure(.response(code: error["code"].intValue, message: error["message"].stringValue))
        } else {
            result = .success(message["result"])
        }
        let waiter = state.withLock { state -> CheckedContinuation<JSON, any Error>? in
            switch state.slots[number] {
            case .pending:
                state.slots[number] = .answered(result)
                return nil
            case .waiting(let continuation):
                state.slots[number] = nil
                return continuation
            case .answered, nil:
                return nil
            }
        }
        waiter?.resume(with: result)
    }

    /// Returns once the server's output has ended, or the caller is cancelled.
    public func waitUntilClosed() async {
        let key = state.withLock { state -> Int in
            state.nextWaiter += 1
            return state.nextWaiter
        }
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let resumeNow = state.withLock { state -> Bool in
                    if state.closed != nil || Task.isCancelled { return true }
                    state.closeWaiters[key] = continuation
                    return false
                }
                if resumeNow { continuation.resume() }
            }
        } onCancel: {
            state.withLock { $0.closeWaiters.removeValue(forKey: key) }?.resume()
        }
    }

    private func close(reason: String) {
        let error = LanguageServerError.connectionClosed(reason: reason)
        let (waiters, closeWaiters) = state.withLock {
            state -> ([CheckedContinuation<JSON, any Error>], [CheckedContinuation<Void, Never>]) in
            state.closed = error
            let closeWaiters = Array(state.closeWaiters.values)
            state.closeWaiters = [:]
            var waiters: [CheckedContinuation<JSON, any Error>] = []
            for (id, slot) in state.slots {
                switch slot {
                case .waiting(let continuation):
                    waiters.append(continuation)
                    state.slots[id] = nil
                case .pending:
                    state.slots[id] = .answered(.failure(error))
                case .answered:
                    break
                }
            }
            return (waiters, closeWaiters)
        }
        for waiter in waiters { waiter.resume(throwing: error) }
        for waiter in closeWaiters { waiter.resume() }
    }

    // MARK: Encoding

    private static func message(id: JSONValue?, method: String, params: JSONValue) -> [UInt8] {
        var object: JSONValue = ["jsonrpc": "2.0", "method": .string(method), "params": params]
        if let id, case .object(var members) = object {
            members["id"] = id
            object = .object(members)
        }
        // A JSONValue built here holds no number that cannot be written, so encoding does not fail.
        return LSPFrame.encode((try? object.encodedBytes()) ?? [])
    }

    private static func nullResult(rawID: [UInt8]) -> [UInt8] {
        LSPFrame.encode(Array(#"{"jsonrpc":"2.0","id":"#.utf8) + rawID + Array(#","result":null}"#.utf8))
    }
}
