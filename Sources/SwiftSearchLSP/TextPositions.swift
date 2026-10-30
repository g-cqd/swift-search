internal import SourceCorpus

/// Converts between swift-search's 1-based UTF-8 columns and LSP's 0-based character offsets, which count UTF-16 code
/// units unless the server agreed to UTF-8. Over analyzerkit's `LineIndex` (its roadmap 0051): lines end at LF, CRLF
/// and CR; ASCII lines convert by arithmetic; an offset inside a surrogate pair names its scalar's start.
struct TextPositions: Sendable {
    private let lines: LineIndex

    init(_ text: String) { lines = LineIndex(Array(text.utf8)) }

    init(bytes: [UInt8]) { lines = LineIndex(bytes) }

    /// The LSP character of the 1-based UTF-8 `column` on 1-based `line`; clamped to the line.
    func character(line: Int, column: Int, utf16: Bool) -> Int {
        let offset = max(column - 1, 0)
        guard utf16 else { return offset }
        return lines.utf16Offset(line: line, utf8Column: column) ?? offset
    }

    /// The 1-based UTF-8 column of the LSP `character` on 0-based `line`; clamped to the line.
    func column(line: Int, character: Int, utf16: Bool) -> Int {
        guard utf16 else { return max(character, 0) + 1 }
        return lines.utf8Column(line: line + 1, utf16Offset: character) ?? max(character, 0) + 1
    }
}
