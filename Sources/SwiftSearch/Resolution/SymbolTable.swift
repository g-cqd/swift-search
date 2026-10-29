/// The declarations and references of a corpus, indexed by name.
public struct SymbolTable: Sendable {
    /// One declaration and the file that holds it.
    public struct Entry: Sendable, Hashable {
        public let file: String
        public let declaration: Declaration
    }

    /// One reference and the file that holds it.
    public struct Use: Sendable, Hashable {
        public let file: String
        public let reference: Reference
    }

    /// Every declaration, in file order then source order.
    public let entries: [Entry]
    /// The files, sorted.
    public let files: [String]
    /// The names of the types the corpus declares.
    public let typeNames: Set<String>
    private let declarationsByName: [String: [Int]]
    private let usesByName: [String: [Use]]

    /// - Complexity: O(*n*) in the number of declarations and references.
    public init(_ symbols: [FileSymbols]) {
        let ordered = symbols.sorted { $0.path < $1.path }
        var entries: [Entry] = []
        var byName: [String: [Int]] = [:]
        var uses: [String: [Use]] = [:]
        for file in ordered {
            for declaration in file.declarations {
                byName[declaration.name, default: []].append(entries.count)
                entries.append(Entry(file: file.path, declaration: declaration))
            }
            for reference in file.references {
                uses[reference.name, default: []].append(Use(file: file.path, reference: reference))
            }
        }
        self.entries = entries
        self.files = ordered.map(\.path)
        self.typeNames = Set(entries.lazy.filter { $0.declaration.kind.isType }.map(\.declaration.name))
        self.declarationsByName = byName
        self.usesByName = uses
    }

    /// The declarations named `name`.
    /// - Complexity: O(1) to find them, O(*k*) to return *k*.
    public func declarations(named name: String) -> [Entry] {
        declarationsByName[name, default: []].map { entries[$0] }
    }

    /// The references to the name `name`.
    public func uses(of name: String) -> [Use] {
        usesByName[name, default: []]
    }
}
