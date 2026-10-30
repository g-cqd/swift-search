import Testing

@testable import SwiftSearchLSP

@Suite struct TextPositionsTests {
    private let positions = TextPositions("let a = 1\nlet 🙂é = 2\r\nx")

    @Test func `converts UTF-8 columns to UTF-16 characters and back`() {
        // `=` on line 2: byte column 11 (4 + 4 bytes of 🙂 + 2 of é + space), UTF-16 offset 7.
        #expect(positions.character(line: 2, column: 12, utf16: true) == 8)
        #expect(positions.column(line: 1, character: 8, utf16: true) == 12)
        #expect(positions.character(line: 1, column: 5, utf16: true) == 4)
    }

    @Test func `passes columns through when the server counts bytes`() {
        #expect(positions.character(line: 2, column: 12, utf16: false) == 11)
        #expect(positions.column(line: 1, character: 11, utf16: false) == 12)
    }

    /// An LSP offset that falls between the two halves of a surrogate pair names the scalar's start, not a replacement
    /// character three bytes long (analyzerkit `LineIndex`, roadmap 0006).
    @Test func `an offset inside a surrogate pair gives the scalar's start`() {
        #expect(positions.column(line: 1, character: 5, utf16: true) == 5)
    }

    @Test func `a CR alone ends a line too`() {
        let positions = TextPositions("a\rb🙂")
        #expect(positions.character(line: 2, column: 6, utf16: true) == 3)
    }

    @Test func `clamps a column past the end of its line`() {
        #expect(positions.character(line: 3, column: 50, utf16: true) == 1)
        #expect(positions.column(line: 2, character: 50, utf16: true) == 2)
    }
}
