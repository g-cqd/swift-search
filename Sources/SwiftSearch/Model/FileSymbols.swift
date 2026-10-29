/// The declarations and references of one source file: what the facts cache stores.
public struct FileSymbols: Sendable, Hashable, Codable {
    public let path: String
    public let declarations: [Declaration]
    public let references: [Reference]
    /// Why the file was not read for symbols (a syntax tree nested too deeply to walk); nil when it was.
    public let degraded: String?

    public init(path: String, declarations: [Declaration], references: [Reference], degraded: String? = nil) {
        self.path = path
        self.declarations = declarations
        self.references = references
        self.degraded = degraded
    }
}
