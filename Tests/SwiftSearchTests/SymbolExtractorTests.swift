import Testing

@testable import SwiftSearch

@Suite struct SymbolExtractorTests {
    private let source = """
        import Foundation

        public struct Outer<T> {
            struct Inner {
                static let shared = Inner()
                func fetch(id: Int, _ name: String) async throws -> Data { Data() }
            }
            var (left, right) = (1, 2)
        }

        public extension Outer.Inner {
            func helper() {
                let local = 1
                func nested() {}
                _ = local
            }
        }

        enum Mode { case on, off }

        protocol Store {
            func load() -> Int
        }

        func topLevel() {}
        """

    private func declaration(_ name: String) throws -> Declaration {
        try #require(symbols(source).declarations.first { $0.name == name })
    }

    @Test func `records every declaration at file and type scope with its kind`() {
        let found = Set(symbols(source).declarations.map { "\($0.kind.rawValue) \($0.name)" })
        #expect(
            found == [
                "import Foundation", "struct Outer", "struct Inner", "constant shared", "method fetch",
                "variable left", "variable right", "extension Inner", "method helper", "enum Mode", "enumCase on",
                "enumCase off", "protocol Store", "method load", "function topLevel",
            ])
    }

    @Test func `leaves out declarations inside bodies`() {
        let names = symbols(source).declarations.map(\.name)
        #expect(!names.contains("local"))
        #expect(!names.contains("nested"))
    }

    @Test func `records the enclosing types outermost first, an extension's as written`() throws {
        #expect(try declaration("fetch").containers == ["Outer", "Inner"])
        #expect(try declaration("helper").containers == ["Outer", "Inner"])
        #expect(try declaration("load").containers == ["Store"])
    }

    @Test func `gives a member the access level of its extension when it writes none`() throws {
        #expect(try declaration("helper").accessLevel == .public)
        #expect(try declaration("fetch").accessLevel == .internal)
        #expect(try declaration("Outer").accessLevel == .public)
    }

    @Test func `records the signature, the location of the name and the extent`() throws {
        let fetch = try declaration("fetch")
        let signature = try #require(fetch.signature)
        #expect(signature.labels == ["id", nil])
        #expect(signature.selector == "(id:_:)")
        #expect(signature.display == "(id: Int, _ name: String) async throws -> Data")
        #expect(fetch.line == 6)
        #expect(fetch.column == 14)
        #expect(try declaration("Outer").endLine == 9)
        #expect(try declaration("Outer").genericParameters == ["T"])
        #expect(try declaration("shared").isStatic)
    }

    @Test func `records how each reference uses its name`() {
        let references = symbols(
            """
            func f() {
                Cache.shared.store(value)
                count += 1
                total = count
                update(&state)
                let x: Model = make()
                Builder().run()
            }
            """
        ).references
        func role(_ name: String) -> Reference.Role? { references.first { $0.name == name }?.role }
        #expect(role("store") == .call)
        #expect(role("shared") == .read)
        #expect(role("count") == .write)
        #expect(role("total") == .write)
        #expect(role("state") == .write)
        #expect(role("Model") == .type)
        #expect(role("make") == .call)
        #expect(references.first { $0.name == "shared" }?.base == "Cache")
        #expect(references.first { $0.name == "store" }?.base == "Cache.shared")
        #expect(references.first { $0.name == "run" }?.base == "Builder")
    }

    @Test func `reports a file too deep to walk instead of walking it`() {
        // A member chain nests one level per link, and the parser does not cap it.
        let deep = "let x = a" + String(repeating: ".b", count: 30_000)
        let result = symbols(deep)
        #expect(result.degraded != nil)
        #expect(result.declarations.isEmpty)
    }
}
