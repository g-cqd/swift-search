/// Converts between swift-search's 1-based UTF-8 columns and LSP's 0-based character offsets, which count UTF-16 code
/// units unless the server agreed to UTF-8.
struct TextPositions: Sendable {
    /// The lines of the file, without their terminators.
    private let lines: [Substring]

    init(_ text: String) {
        // `\r\n` is one Character, so splitting on "\n" alone would keep it; the compiler ends a line at all three.
        lines = text.split(omittingEmptySubsequences: false) { $0 == "\n" || $0 == "\r\n" || $0 == "\r" }
    }

    /// The LSP character of the 1-based UTF-8 `column` on 1-based `line`; clamped to the line.
    func character(line: Int, column: Int, utf16: Bool) -> Int {
        let offset = max(column - 1, 0)
        guard utf16, line >= 1, line <= lines.count else { return offset }
        let text = lines[line - 1].utf8
        let end = text.index(text.startIndex, offsetBy: min(offset, text.count))
        return String(decoding: text[text.startIndex..<end], as: UTF8.self).utf16.count
    }

    /// The 1-based UTF-8 column of the LSP `character` on 0-based `line`; clamped to the line.
    func column(line: Int, character: Int, utf16: Bool) -> Int {
        guard utf16, line >= 0, line < lines.count else { return max(character, 0) + 1 }
        let text = lines[line].utf16
        let end = text.index(text.startIndex, offsetBy: min(max(character, 0), text.count))
        return String(decoding: Array(text[text.startIndex..<end]), as: UTF16.self).utf8.count + 1
    }
}
