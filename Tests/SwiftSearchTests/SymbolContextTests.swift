import Foundation
import Testing

@testable import SwiftSearch

@Suite struct SymbolContextTests {
    private let source = """
        struct Box {
            /// Stores a value.
            ///
            /// - Parameters:
            ///   - value: what to store.
            ///   - key: where.
            /// - Returns: the previous value.
            /// - Throws: `Full` when no slot is free.
            @discardableResult
            mutating func put(_ value: Int, key: String) throws -> Int? {
                let old = slots[key]
                slots[key] = value
                return old
            }
        }
        """

    private func context(_ options: SymbolContextOptions) throws -> SymbolContext {
        try #require(
            SymbolContextExtractor.context(source: source, file: "/f.swift", line: 10, column: 19, options: options))
    }

    @Test func `reads the documentation's summary and fields`() throws {
        let documentation = try #require(try context(.init(documentation: true)).documentation)
        #expect(documentation.summary == "Stores a value.")
        #expect(documentation.parameters == ["value": "what to store.", "key": "where."])
        #expect(documentation.returns == "the previous value.")
        #expect(documentation.throws == "`Full` when no slot is free.")
    }

    @Test func `gives the signature up to the body, attributes included`() throws {
        #expect(
            try context(.init(signature: true)).signature
                == "@discardableResult\n    mutating func put(_ value: Int, key: String) throws -> Int?")
    }

    @Test func `gives the body, the enclosing scope and the lines around the name`() throws {
        let found = try context(.init(linesBefore: 1, linesAfter: 1, body: true, scope: true))
        #expect(found.body?.hasPrefix("{") == true)
        #expect(found.body?.contains("slots[key] = value") == true)
        #expect(found.scope == SymbolContext.Scope(kind: "struct", name: "Box", startLine: 1, endLine: 15))
        #expect(found.lines.map(\.number) == [9, 10, 11])
        #expect(found.lines.map(\.isDeclaration) == [false, true, false])
    }

    @Test func `cuts a long body and says so`() throws {
        let body = (0..<(SymbolContextOptions.maximumBodyLines + 10)).map { "    _ = \($0)" }.joined(separator: "\n")
        let long = "func f() {\n" + body + "\n}"
        let found = try #require(
            SymbolContextExtractor.context(
                source: long, file: "/f.swift", line: 1, column: 6, options: .init(body: true)))
        #expect(found.bodyIsTruncated)
        #expect(
            found.body?.split(separator: "\n", omittingEmptySubsequences: false).count
                == SymbolContextOptions.maximumBodyLines)
    }

    @Test func `returns nothing for a line outside the file`() {
        #expect(
            SymbolContextExtractor.context(source: source, file: "/f.swift", line: 99, column: 1, options: .all) == nil)
    }

    @Test func `numbers lines as the compiler does when they end with CRLF`() throws {
        let crlf = source.replacingOccurrences(of: "\n", with: "\r\n")
        let found = try #require(
            SymbolContextExtractor.context(
                source: crlf, file: "/f.swift", line: 10, column: 19, options: .init(linesBefore: 1, linesAfter: 1)))
        #expect(found.lines.map(\.number) == [9, 10, 11])
        #expect(found.lines[1].text == "    mutating func put(_ value: Int, key: String) throws -> Int? {")
    }
}
