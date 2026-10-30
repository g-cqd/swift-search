internal import AemiJSON
public import AemiJSONRPC
internal import AemiRuntime
public import SwiftSearchLSP
internal import Synchronization

#if canImport(System)
    internal import System
#else
    internal import SystemPackage
#endif

/// The stdio transport of MCP: one JSON-RPC message per line in, one per line out. Lines are split by AemiJSONRPC's
/// `LineFraming` over blocks of input (roadmap 0007): standard input is read 64 KiB at a time, not a byte per call (H8).
public enum MCPStdio {
    /// The longest line read, in bytes; a longer one is answered with a parse error and dropped.
    public static let maximumLineLength = LineFraming.defaultMaximumLineLength
    /// The most requests handled at once; further lines wait.
    public static let maximumConcurrentRequests = 8

    /// Serves `server` on the lines of `input` until it ends, writing each answer as a line to `output`, then shuts
    /// `pool` down and waits for its sessions to stop.
    @concurrent public static func serve(
        _ server: MCPServer, input: some AsyncSequence<[UInt8], any Error>, output: any MessageSink,
        pool: LanguageServerPool?
    ) async {
        await withTaskGroup(of: Void.self) { group in
            if let pool { group.addTask { await pool.run() } }
            await withTaskGroup(of: Void.self) { requests in
                var inFlight = 0
                var framing = LineFraming(maximumLineLength: maximumLineLength)
                do {
                    for try await chunk in input {
                        for line in framing.append(chunk) {
                            guard case .message(let message) = line else {
                                try? await output.write(
                                    MCPServer.failure(
                                        id: .null, code: -32700,
                                        message: "parse error: a line is longer than \(maximumLineLength) bytes")
                                        + [UInt8(ascii: "\n")])
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
                    }
                } catch {
                    // The input broke: stop reading, finish what is in flight.
                }
            }
            pool?.shutdown()
        }
    }

    /// Serves `server` on the lines read from `descriptor`, a block at a time on a thread of an offload pool so a
    /// blocking `read` never holds a thread of the cooperative pool. The descriptor is not closed.
    public static func serve(
        _ server: MCPServer, descriptor: Int32, output: any MessageSink, pool: LanguageServerPool?
    ) async {
        let reader = BlockingOffloadPool(width: 1)
        await serve(
            server, input: FileDescriptorChunks(descriptor: descriptor, pool: reader), output: output, pool: pool)
        reader.shutdown()
    }

    /// Serves `server` on the process's standard input and output.
    public static func serveStandardStreams(_ server: MCPServer, pool: LanguageServerPool?) async {
        await serve(server, descriptor: FileDescriptor.standardInput.rawValue, output: StandardOutput(), pool: pool)
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
