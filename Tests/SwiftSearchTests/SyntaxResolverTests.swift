import Testing

@testable import SwiftSearch

@Suite struct SyntaxResolverTests {
    private let corpus = table(
        """
        struct Outer {
            struct Inner {
                func leaf() {}
                func fetch(id: Int) {}
                func fetch(_ id: Int) {}
            }
            func leaf() {}
        }
        struct Other { func leaf() {} }
        func load() {}
        func loadUsers() {}
        func download() {}
        func use() {
            Other().leaf()
            Outer.Inner().leaf()
            load()
        }
        """)

    private func resolve(_ query: String) throws -> [String] {
        try SyntaxResolver.resolve(QueryParser.parse(query), in: corpus).map(\.qualifiedSelector)
    }

    @Test func `finds every declaration of a simple name`() throws {
        #expect(try resolve("leaf") == ["Outer.Inner.leaf()", "Outer.leaf()", "Other.leaf()"])
    }

    @Test func `finds a member through the whole chain of its enclosing types`() throws {
        #expect(try resolve("Outer.Inner.leaf") == ["Outer.Inner.leaf()"])
        #expect(try resolve("Inner.leaf") == ["Outer.Inner.leaf()"])
        #expect(try resolve("Outer.leaf") == ["Outer.leaf()"])
        #expect(try resolve("Missing.leaf").isEmpty)
    }

    @Test func `tells overloads apart by their labels`() throws {
        #expect(try resolve("fetch(id:)") == ["Outer.Inner.fetch(id:)"])
        #expect(try resolve("Inner.fetch(_:)") == ["Outer.Inner.fetch(_:)"])
        #expect(try resolve("fetch()").isEmpty)
    }

    @Test func `matches a regex against whole names`() throws {
        #expect(try resolve("/load/") == ["load()"])
        #expect(try resolve("/load.*/") == ["load()", "loadUsers()"])
    }

    @Test func `finds nothing for a USR without an index`() throws {
        #expect(try resolve("s:4main5OuterV").isEmpty)
    }

    @Test func `reports uses of the name except through a base that names another type`() throws {
        let leaf = try #require(SyntaxResolver.resolve(.qualified(types: ["Other"], name: "leaf"), in: corpus).first)
        let uses = SyntaxResolver.uses(of: leaf, in: corpus)
        #expect(uses.map(\.line) == [14])
        #expect(uses.allSatisfy { !$0.isResolved && $0.role == .call })
    }
}

@Suite struct CallLabelTests {
    private static let signature = FunctionSignature(parameters: [
        .init(label: nil, name: "value", type: "Int"), .init(label: "by", name: "step", type: "Int"),
        .init(label: "values", name: "values", type: "Int..."), .init(label: "then", name: "then", type: "() -> Void"),
    ])

    @Test(
        arguments: [
            ([nil, "by"], true),
            ([nil], true),
            (["by"], true),
            ([nil, "values", nil, nil], true),
            ([nil, "then"], true),
            (["by", nil], false),
            (["with"], false),
            ([nil, nil], false),
        ] as [([String?], Bool)])
    func `admits a call whose labels the parameters can take, in order`(labels: [String?], admitted: Bool) {
        let call = Reference(name: "f", line: 1, column: 1, role: .call, arguments: labels)
        #expect(call.canCall(Self.signature) == admitted)
    }

    @Test func `leaves out calls whose labels another overload takes`() throws {
        let corpus = table(
            """
            struct Index { func find(name: String) {} }
            func use(index: Index, finder: Finder) {
                index.find(name: "a")
                finder.find("a")
            }
            """)
        let find = try #require(SyntaxResolver.resolve(.name("find"), in: corpus).first)
        #expect(SyntaxResolver.uses(of: find, in: corpus).map(\.line) == [3])
    }

    @Test func `leaves out uses of an enum case whose labels another case of the name takes`() throws {
        let corpus = table(
            """
            enum RecorderError: Error { case invalid(from: Int, action: String) }
            enum EngineError: Error { case invalid(from: Int, calling: String) }
            func use(error: RecorderError) throws {
                throw .invalid(from: 1, action: "start")
                throw EngineError.invalid(from: 1, calling: "start")
                switch error {
                case .invalid(let from, let action): _ = (from, action)
                case .invalid(from: let from, action: _): _ = from
                case .invalid(let payload): _ = payload
                }
                if case .invalid(from: _, calling: _) = error {}
            }
            """)
        let invalid = try #require(
            SyntaxResolver.resolve(.qualified(types: ["RecorderError"], name: "invalid"), in: corpus).first)
        #expect(invalid.signature?.selector == "(from:action:)")
        #expect(SyntaxResolver.uses(of: invalid, in: corpus).map(\.line) == [4, 7, 8, 9])
        #expect(
            try SyntaxResolver.resolve(QueryParser.parse("invalid(from:calling:)"), in: corpus).map(\.qualifiedSelector)
                == ["EngineError.invalid(from:calling:)"])
    }

    @Test func `leaves out a pattern without labels whose subject's written type is another enum`() throws {
        let corpus = table(
            """
            enum RecorderError: Error { case invalid(from: Int, action: String) }
            extension Engine {
                enum Failure: Error {
                    case invalid(from: Int, calling: String)
                    var text: String {
                        switch self {
                        case .invalid(let from, let calling): "\\(from) \\(calling)"
                        }
                    }
                }
            }
            func use(error: RecorderError, failure: Engine.Failure?, unknown: Any) {
                switch error { case .invalid(let from, let action): _ = (from, action) }
                if case .invalid(let payload) = failure { _ = payload }
                guard case .invalid(let payload) = unknown else { return }
                switch failure {
                case .some(.invalid(let from, _)): _ = from
                default: break
                }
            }
            """)
        let invalid = try #require(
            SyntaxResolver.resolve(.qualified(types: ["RecorderError"], name: "invalid"), in: corpus).first)
        // Kept: the subject is a RecorderError (13), of no type the syntax can read (15), or nested in another
        // pattern (17).
        #expect(SyntaxResolver.uses(of: invalid, in: corpus).map(\.line) == [13, 15, 17])
        let failure = try #require(
            SyntaxResolver.resolve(.qualified(types: ["Failure"], name: "invalid"), in: corpus).first)
        #expect(SyntaxResolver.uses(of: failure, in: corpus).map(\.line) == [7, 14, 15, 17])
    }

    @Test func `leaves out calls of a name that a property with a non-function type cannot answer`() throws {
        let corpus = table(
            """
            struct Position { var location: String { "" } }
            func use(position: Position, converter: Converter) {
                _ = position.location
                _ = converter.location(for: 1)
            }
            """)
        let location = try #require(SyntaxResolver.resolve(.name("location"), in: corpus).first)
        #expect(SyntaxResolver.uses(of: location, in: corpus).map(\.line) == [3])
    }
}
