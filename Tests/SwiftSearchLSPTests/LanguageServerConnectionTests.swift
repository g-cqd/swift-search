import AemiJSON
import Synchronization
import Testing

@testable import SwiftSearchLSP

/// A server in the test: it sees each message the connection writes and answers through `output`.
private final class ScriptedServer: MessageSink {
    typealias Script =
        @Sendable (_ message: JSON, _ reply: @Sendable ([UInt8]) -> Void, _ end: @Sendable () -> Void)
        -> Void

    let output: AsyncThrowingStream<[UInt8], any Error>
    private let continuation: AsyncThrowingStream<[UInt8], any Error>.Continuation
    private let script: Script
    let written = Mutex<[[UInt8]]>([])

    init(_ script: @escaping Script) {
        (output, continuation) = AsyncThrowingStream.makeStream()
        self.script = script
    }

    func write(_ bytes: [UInt8]) async throws {
        var decoder = LSPFrameDecoder()
        for body in try decoder.append(bytes) {
            written.withLock { $0.append(body) }
            let message = try AemiJSON.parse(body).root
            script(message, { self.continuation.yield(LSPFrame.encode($0)) }, { self.continuation.finish() })
        }
    }

    func end() { continuation.finish() }
}

private func response(id: Int, result: String) -> [UInt8] {
    Array(#"{"jsonrpc":"2.0","id":\#(id),"result":\#(result)}"#.utf8)
}

@Suite struct LanguageServerConnectionTests {
    @Test func `matches responses to requests by id, in any order`() async throws {
        let held = Mutex<[Int]>([])
        let server = ScriptedServer { message, reply, _ in
            // Answer the second request first, then the first.
            let id = message["id"].intValue
            let waiting = held.withLock { held -> [Int] in
                held.append(id)
                return held.count == 2 ? held : []
            }
            for id in waiting.reversed() { reply(response(id: id, result: "\(id * 10)")) }
        }
        let connection = LanguageServerConnection(sink: server)
        let reader = Task { await connection.run(reading: server.output) }
        async let first = connection.request("a", [:])
        async let second = connection.request("b", [:])
        let results = try await [first.intValue, second.intValue]
        #expect(results.sorted() == [10, 20])
        server.end()
        await reader.value
    }

    @Test func `throws the server's error`() async throws {
        let server = ScriptedServer { message, reply, _ in
            reply(
                Array(#"{"jsonrpc":"2.0","id":\#(message["id"].intValue),"error":{"code":-32601,"message":"no"}}"#.utf8)
            )
        }
        let connection = LanguageServerConnection(sink: server)
        let reader = Task { await connection.run(reading: server.output) }
        await #expect(throws: LanguageServerError.response(code: -32601, message: "no")) {
            try await connection.request("missing", [:])
        }
        server.end()
        await reader.value
    }

    @Test func `answers the server's own requests with null`() async throws {
        let server = ScriptedServer { message, reply, _ in
            if message["method"].string == "a" {
                reply(
                    Array(#"{"jsonrpc":"2.0","id":"sk-1","method":"window/workDoneProgress/create","params":{}}"#.utf8))
                reply(response(id: message["id"].intValue, result: "true"))
            }
        }
        let connection = LanguageServerConnection(sink: server)
        let reader = Task { await connection.run(reading: server.output) }
        _ = try await connection.request("a", [:])
        server.end()
        await reader.value
        let answers = server.written.withLock { $0 }.compactMap { try? AemiJSON.parse($0).root }
        #expect(answers.contains { $0["id"].string == "sk-1" && $0["result"].isNull })
    }

    @Test func `fails requests in flight and later ones when the output ends`() async throws {
        // The server ends its output as soon as it has the request.
        let server = ScriptedServer { _, _, end in end() }
        let connection = LanguageServerConnection(sink: server)
        let reader = Task { await connection.run(reading: server.output) }
        await #expect(throws: LanguageServerError.connectionClosed(reason: "the server's output ended")) {
            try await connection.request("a", [:])
        }
        await reader.value
        await #expect(throws: LanguageServerError.connectionClosed(reason: "the server's output ended")) {
            try await connection.request("b", [:])
        }
    }

    @Test func `gives up on a request at its deadline`() async throws {
        let server = ScriptedServer { _, _, _ in }
        let connection = LanguageServerConnection(sink: server)
        let reader = Task { await connection.run(reading: server.output) }
        await #expect(throws: LanguageServerError.timedOut(method: "slow", after: .milliseconds(50))) {
            try await connection.request("slow", [:], timeout: .milliseconds(50))
        }
        server.end()
        await reader.value
    }
}
