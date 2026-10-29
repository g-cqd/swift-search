import Testing

@testable import SwiftSearch

@Suite struct QueryParserTests {
    @Test(arguments: [
        ("shared", SymbolQuery.Pattern.name("shared")),
        ("  shared\n", .name("shared")),
        ("Monitor.shared", .qualified(types: ["Monitor"], name: "shared")),
        ("Outer.Inner<T>.leaf", .qualified(types: ["Outer", "Inner<T>"], name: "leaf")),
        ("fetch()", .selector(types: [], name: "fetch", labels: [])),
        ("fetch(id:_:)", .selector(types: [], name: "fetch", labels: ["id", nil])),
        ("Client.fetch(id:)", .selector(types: ["Client"], name: "fetch", labels: ["id"])),
        ("s:4main3FooV", .usr("s:4main3FooV")),
        ("c:objc(cs)NSObject", .usr("c:objc(cs)NSObject")),
        ("/load.*/", .regex("load.*")),
        ("==", .name("==")),
    ])
    func `parses each query form`(input: String, expected: SymbolQuery.Pattern) throws {
        #expect(try QueryParser.parse(input) == expected)
    }

    @Test(arguments: ["", "   ", "Foo..bar", ".bar", "Foo.", "fetch(id)", "fetch(id x:)", "a b", "Foo<T.bar"])
    func `refuses a malformed query`(input: String) {
        #expect(throws: QueryParseError.self) { try QueryParser.parse(input) }
    }

    @Test func `refuses a backreference, which a linear-time engine cannot run`() {
        #expect {
            try QueryParser.parse(#"/(a)\1/"#)
        } throws: { error in
            guard case QueryParseError.invalidRegex = error else { return false }
            return true
        }
    }

    @Test func `refuses a query longer than the limit`() {
        let input = String(repeating: "a", count: QueryParser.maximumLength + 1)
        #expect(throws: QueryParseError.tooLong(QueryParser.maximumLength)) { try QueryParser.parse(input) }
    }
}

@Suite struct NameExpressionTests {
    @Test func `matches the whole name, not a part of it`() throws {
        let expression = try NameExpression("load")
        #expect(expression.matches("load"))
        #expect(!expression.matches("loadUsers"))
        #expect(!expression.matches("download"))
    }

    @Test func `matches a whole name an alternative gives, not only the leftmost one`() throws {
        #expect(try NameExpression("a|ab").matches("ab"))
    }

    @Test func `answers a pattern that backtracking engines take exponential time on`() throws {
        let expression = try NameExpression("(a+)+b")
        #expect(!expression.matches(String(repeating: "a", count: 4096)))
    }
}
