import Testing

@testable import SwiftSearchLSP

@Suite struct LSPFrameTests {
    private let messages = [Array(#"{"id":1}"#.utf8), Array(#"{"id":2,"result":"é"}"#.utf8)]

    @Test func `decodes frames however the stream is cut`() throws {
        let stream = messages.flatMap(LSPFrame.encode)
        for size in [1, 3, 7, stream.count] {
            var decoder = LSPFrameDecoder()
            var bodies: [[UInt8]] = []
            var offset = 0
            while offset < stream.count {
                bodies += try decoder.append(stream[offset..<min(offset + size, stream.count)])
                offset += size
            }
            #expect(bodies == messages, "chunks of \(size) bytes")
        }
    }

    @Test func `reads the length from any header line, in any case`() throws {
        var decoder = LSPFrameDecoder()
        let framed = Array("Content-Type: application/vscode-jsonrpc\r\ncontent-length: 2\r\n\r\n{}".utf8)
        #expect(try decoder.append(framed) == [Array("{}".utf8)])
    }

    @Test(arguments: [
        ("Content-Length: x\r\n\r\n", LSPFrame.Failure.missingContentLength),
        ("Content-Type: a\r\n\r\n", .missingContentLength),
        ("Content-Length: -1\r\n\r\n", .missingContentLength),
        ("Content-Length: 99999999999\r\n\r\n", .contentTooLong(99_999_999_999)),
    ])
    func `refuses a header it cannot trust`(header: String, failure: LSPFrame.Failure) {
        var decoder = LSPFrameDecoder()
        #expect(throws: failure) { try decoder.append(Array(header.utf8)) }
    }

    @Test func `refuses a header that never ends`() {
        var decoder = LSPFrameDecoder()
        let endless = [UInt8](repeating: UInt8(ascii: "a"), count: LSPFrame.maximumHeaderLength + 1)
        #expect(throws: LSPFrame.Failure.headerTooLong) { try decoder.append(endless) }
    }
}

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

    @Test func `clamps a column past the end of its line`() {
        #expect(positions.character(line: 3, column: 50, utf16: true) == 1)
        #expect(positions.column(line: 2, character: 50, utf16: true) == 2)
    }
}
