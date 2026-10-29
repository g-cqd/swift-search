internal import AemiJSON
internal import AemiRuntime
public import SwiftSearchLSP
internal import Synchronization

#if canImport(System)
    internal import System
#else
    internal import SystemPackage
#endif

/// The stdio transport of MCP: one JSON-RPC message per line in, one per line out.
public enum MCPStdio {
    /// The longest line read, in bytes; a longer one is answered with a parse error and dropped.
    public static let maximumLineLength = 8 << 20
    /// The most requests handled at once; further lines wait.
    public static let maximumConcurrentRequests = 8

    /// Serves `server` on `input` until it ends, writing each answer as a line to `output`, then shuts `pool` down and
    /// waits for its sessions to stop.
    public static func serve(
        _ server: MCPServer, input: some AsyncSequence<UInt8, any Error>, output: any MessageSink,
        pool: LanguageServerPool?
    ) async {
        await withTaskGroup(of: Void.self) { group in
            if let pool { group.addTask { await pool.run() } }
            await withTaskGroup(of: Void.self) { requests in
                var inFlight = 0
                var line: [UInt8] = []
                var overlong = false
                do {
                    for try await byte in input {
                        guard byte == UInt8(ascii: "\n") else {
                            if line.count < maximumLineLength { line.append(byte) } else { overlong = true }
                            continue
                        }
                        let message = line
                        let refused = overlong
                        line.removeAll(keepingCapacity: true)
                        overlong = false
                        if refused {
                            try? await output.write(
                                MCPServer.failure(
                                    id: .null, code: -32700,
                                    message: "parse error: a line is longer than "
                                        + "\(maximumLineLength) bytes") + [UInt8(ascii: "\n")])
                            continue
                        }
                        guard message.contains(where: { $0 != UInt8(ascii: " ") && $0 != UInt8(ascii: "\r") }) else {
                            continue
                        }
                        if inFlight == maximumConcurrentRequests {
                            await requests.next()
                            inFlight -= 1
                        }
                        inFlight += 1
                        requests.addTask {
                            if let answer = await server.handle(message) {
                                try? await output.write(answer + [UInt8(ascii: "\n")])
                            }
                        }
                    }
                } catch {
                    // The input broke: stop reading, finish what is in flight.
                }
            }
            pool?.shutdown()
        }
    }

    /// Serves `server` on the process's standard input and output.
    public static func serveStandardStreams(_ server: MCPServer, pool: LanguageServerPool?) async {
        let reader = BlockingOffloadPool(width: 1)
        await serve(server, input: StandardInput(reader: reader), output: StandardOutput(), pool: pool)
        reader.shutdown()
    }
}

/// The process's standard output, one whole write at a time.
public final class StandardOutput: MessageSink {
    private let lock = Mutex(())

    public init() {}

    public func write(_ bytes: [UInt8]) async throws {
        try lock.withLock { _ in
            _ = try FileDescriptor.standardOutput.writeAll(bytes)
        }
    }
}

/// The process's standard input as bytes, read in blocks on a thread of aemi's offload pool, so a blocking `read`
/// never holds a thread of the cooperative pool.
struct StandardInput: AsyncSequence {
    typealias Element = UInt8
    typealias Failure = any Error

    let reader: BlockingOffloadPool

    struct AsyncIterator: AsyncIteratorProtocol {
        let reader: BlockingOffloadPool
        private var buffer: [UInt8] = []
        private var index = 0
        private var ended = false

        init(reader: BlockingOffloadPool) {
            self.reader = reader
        }

        mutating func next() async throws -> UInt8? {
            if index == buffer.count {
                guard !ended else { return nil }
                buffer = try await read()
                index = 0
                if buffer.isEmpty {
                    ended = true
                    return nil
                }
            }
            defer { index += 1 }
            return buffer[index]
        }

        mutating func next(isolation actor: isolated (any Actor)?) async throws -> UInt8? {
            try await next()
        }

        /// One block of standard input; empty at its end.
        private func read() async throws -> [UInt8] {
            try await reader.run {
                var block = [UInt8](repeating: 0, count: 64 << 10)
                let count = try block.withUnsafeMutableBytes { raw in
                    try unsafe FileDescriptor.standardInput.read(into: raw, retryOnInterrupt: true)
                }
                block.removeSubrange(count...)
                return block
            }
        }
    }

    func makeAsyncIterator() -> AsyncIterator { AsyncIterator(reader: reader) }
}
