import AemiJSON
import Foundation
import Synchronization
import Testing

@testable import SwiftSearch
@testable import SwiftSearchLSP
@testable import SwiftSearchMCP

/// A directory of Swift files under the temporary directory, spelled as the corpus spells it.
private struct Project {
    let root: String

    init() throws {
        root =
            FileManager.default.temporaryDirectory.appendingPathComponent("swift-search-mcp-\(UUID().uuidString)")
            .standardized.resolvingSymlinksInPath().path
        try FileManager.default.createDirectory(atPath: root + "/Sources", withIntermediateDirectories: true)
        try """
        /// Talks to the API.
        public struct Client {
            public func fetch(id: Int) -> String { "" }
        }
        func run(client: Client) { _ = client.fetch(id: 1) }
        """.write(toFile: root + "/Sources/Client.swift", atomically: true, encoding: .utf8)
    }

    func remove() { try? FileManager.default.removeItem(atPath: root) }
}

private func server(_ project: Project, languageServers: (any LanguageServerProvider)? = nil) -> MCPServer {
    MCPServer(root: project.root, cacheRoot: nil, languageServers: languageServers)
}

private func call(_ server: MCPServer, _ line: String) async throws -> JSON {
    let answer = try #require(await server.handle(Array(line.utf8)))
    return try AemiJSON.parse(answer).root
}

/// The JSON a tool wrote as its text content.
private func toolText(_ answer: JSON) throws -> JSON {
    try AemiJSON.parse(try #require(answer["result"]["content"][index: 0]["text"].string)).root
}

/// A provider that is never asked: the tools that need it are only listed.
private struct UnusedProvider: LanguageServerProvider {
    func session(for workspace: String) async throws -> LanguageServerSession {
        throw LanguageServerError.serverNotFound("not in tests")
    }
}

@Suite struct MCPServerTests {
    @Test(arguments: [("2025-06-18", "2025-06-18"), ("2024-11-05", "2024-11-05"), ("1999-01-01", "2025-11-25")])
    func `answers the offered protocol version when it knows it, its newest otherwise`(
        offered: String, answered: String
    )
        async throws
    {
        let project = try Project()
        defer { project.remove() }
        let answer = try await call(
            server(project),
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"\#(offered)"}}"#)
        #expect(answer["result"]["protocolVersion"].string == answered)
        #expect(answer["result"]["serverInfo"]["name"].string == "swift-search")
        #expect(answer["id"].int == 1)
    }

    @Test func `lists the sourcekit-lsp tools only when it has sourcekit-lsp`() async throws {
        let project = try Project()
        defer { project.remove() }
        let request = #"{"jsonrpc":"2.0","id":"a","method":"tools/list"}"#
        let without = try await call(server(project), request)["result"]["tools"].arrayValue.map(\.name.stringValue)
        let with = try await call(server(project, languageServers: UnusedProvider()), request)["result"]["tools"]
            .arrayValue.map(\.name.stringValue)
        #expect(without == ["search_symbols", "find_usages"])
        #expect(with.count == 9)
        #expect(with.contains("lsp_callers"))
    }

    @Test func `searches symbols with their context, paths relative to the root`() async throws {
        let project = try Project()
        defer { project.remove() }
        let answer = try await call(
            server(project),
            #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"search_symbols","arguments":{"query":"Client","kind":"struct","documentation":true}}}"#
        )
        #expect(answer["result"]["isError"].bool == false)
        let matches = try toolText(answer)["matches"].arrayValue
        #expect(matches.map(\.location.stringValue) == ["Sources/Client.swift:2:15"])
        #expect(matches.first?["context"]["documentation"]["summary"].string == "Talks to the API.")
    }

    @Test func `finds usages`() async throws {
        let project = try Project()
        defer { project.remove() }
        let answer = try await call(
            server(project),
            #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"find_usages","arguments":{"query":"Client.fetch(id:)"}}}"#
        )
        let usages = try toolText(answer)["usages"].arrayValue
        #expect(usages.map(\.location.stringValue) == ["Sources/Client.swift:5:39"])
        #expect(usages.first?["resolved"].bool == false)
    }

    @Test(arguments: [
        #"{"query":""}"#, #"{"query":"a..b"}"#, #"{"query":"x","limit":0}"#, #"{"query":"x","kind":"widget"}"#,
        #"{"query":"x","paths":"missing"}"#, #"{"query":"s:4main1xV"}"#,
    ])
    func `reports bad arguments as a tool error`(arguments: String) async throws {
        let project = try Project()
        defer { project.remove() }
        let answer = try await call(
            server(project),
            #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"search_symbols","arguments":\#(arguments)}}"#
        )
        #expect(answer["result"]["isError"].bool == true)
        #expect(answer["result"]["content"][index: 0]["text"].string?.isEmpty == false)
    }

    @Test func `answers protocol errors with their JSON-RPC codes`() async throws {
        let project = try Project()
        defer { project.remove() }
        let server = server(project)
        #expect(try await call(server, "not json")["error"]["code"].int == -32700)
        #expect(try await call(server, "[1]")["error"]["code"].int == -32600)
        #expect(
            try await call(server, #"{"jsonrpc":"2.0","id":5,"method":"resources/list"}"#)["error"]["code"].int
                == -32601)
        #expect(
            try await call(server, #"{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"nope"}}"#)[
                "error"][
                    "code"
                ].int == -32602)
        #expect(await server.handle(Array(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#.utf8)) == nil)
    }

    @Test func `sends no answer to a request the client cancelled`() async throws {
        let project = try Project()
        defer { project.remove() }
        let server = server(project)
        _ = await server.handle(
            Array(#"{"jsonrpc":"2.0","method":"notifications/cancelled","params":{"requestId":7}}"#.utf8))
        #expect(await server.handle(Array(#"{"jsonrpc":"2.0","id":7,"method":"ping"}"#.utf8)) == nil)
        #expect(await server.handle(Array(#"{"jsonrpc":"2.0","id":8,"method":"ping"}"#.utf8)) != nil)
    }
}

/// Collects what the transport writes.
private final class Collected: MessageSink {
    let lines = Mutex<[String]>([])

    func write(_ bytes: [UInt8]) async throws {
        lines.withLock { $0.append(String(decoding: bytes, as: UTF8.self)) }
    }
}

@Suite struct MCPStdioTests {
    @Test func `answers each line, refuses an overlong one, and stops at the end of the input`() async throws {
        let project = try Project()
        defer { project.remove() }
        let overlong = String(repeating: "x", count: MCPStdio.maximumLineLength + 1)
        let input =
            #"{"jsonrpc":"2.0","id":1,"method":"ping"}"# + "\n\n" + overlong + "\n"
            + #"{"jsonrpc":"2.0","id":2,"method":"ping"}"# + "\r\n"
        let output = Collected()
        await MCPStdio.serve(
            server(project), input: Array(input.utf8).async, output: output, pool: nil)
        let lines = output.lines.withLock { $0 }
        #expect(lines.count == 3)
        #expect(lines.allSatisfy { $0.hasSuffix("\n") })
        #expect(lines.contains { $0.contains(#""id":1"#) })
        #expect(lines.contains { $0.contains(#""id":2"#) })
        #expect(lines.contains { $0.contains("-32700") })
    }
}

extension Array where Element == UInt8 {
    /// The bytes as an asynchronous sequence that can throw, as standard input is.
    fileprivate var async: AsyncThrowingStream<UInt8, any Error> {
        AsyncThrowingStream { continuation in
            for byte in self { continuation.yield(byte) }
            continuation.finish()
        }
    }
}
