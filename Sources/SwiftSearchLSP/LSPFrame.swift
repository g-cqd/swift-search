/// The base protocol's framing: `Content-Length: N\r\n\r\n` and N bytes of JSON.
public enum LSPFrame {
    /// The longest header block read, in bytes; a longer one is a broken or hostile stream.
    public static let maximumHeaderLength = 8 << 10
    /// The longest message body accepted, in bytes.
    public static let maximumContentLength = 64 << 20

    /// `body` with its header.
    public static func encode(_ body: [UInt8]) -> [UInt8] {
        var bytes = Array("Content-Length: \(body.count)\r\n\r\n".utf8)
        bytes.reserveCapacity(bytes.count + body.count)
        bytes += body
        return bytes
    }

    /// Why a stream is not a sequence of frames.
    public enum Failure: Error, Sendable, Equatable, CustomStringConvertible {
        case headerTooLong
        case missingContentLength
        case contentTooLong(Int)

        public var description: String {
            switch self {
            case .headerTooLong: "a message header is longer than \(LSPFrame.maximumHeaderLength) bytes"
            case .missingContentLength: "a message header has no valid Content-Length"
            case .contentTooLong(let length):
                "a message announces \(length) bytes, more than \(LSPFrame.maximumContentLength)"
            }
        }
    }
}

/// Splits a byte stream into message bodies, however the stream is chunked.
public struct LSPFrameDecoder: Sendable {
    private var buffer: [UInt8] = []
    /// Bytes of `buffer` already consumed; compacted when it passes half the buffer.
    private var start = 0

    public init() {}

    /// Appends `bytes` and returns every body now complete, in order.
    /// - Throws: ``LSPFrame/Failure`` when the stream is not framed or exceeds a limit; the decoder is then unusable.
    /// - Complexity: amortized O(*n*) in the bytes appended.
    public mutating func append(_ bytes: some Sequence<UInt8>) throws(LSPFrame.Failure) -> [[UInt8]] {
        buffer.append(contentsOf: bytes)
        var bodies: [[UInt8]] = []
        while let body = try next() { bodies.append(body) }
        if start > buffer.count / 2 {
            buffer.removeFirst(start)
            start = 0
        }
        return bodies
    }

    private mutating func next() throws(LSPFrame.Failure) -> [UInt8]? {
        guard let separator = headerEnd() else {
            if buffer.count - start > LSPFrame.maximumHeaderLength { throw .headerTooLong }
            return nil
        }
        guard separator - start <= LSPFrame.maximumHeaderLength else { throw .headerTooLong }
        let length = try contentLength(buffer[start..<separator])
        let bodyStart = separator + 4
        guard buffer.count - bodyStart >= length else { return nil }
        let body = Array(buffer[bodyStart..<(bodyStart + length)])
        start = bodyStart + length
        return body
    }

    /// The index of the `\r\n\r\n` that ends the header at `start`.
    private func headerEnd() -> Int? {
        var index = start
        while index + 3 < buffer.count {
            if buffer[index] == 13, buffer[index + 1] == 10, buffer[index + 2] == 13, buffer[index + 3] == 10 {
                return index
            }
            index += 1
        }
        return nil
    }

    private func contentLength(_ header: ArraySlice<UInt8>) throws(LSPFrame.Failure) -> Int {
        let text = String(decoding: header, as: UTF8.self)
        for line in text.split(separator: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2, parts[0].lowercased() == "content-length" else { continue }
            let digits = parts[1].drop { $0 == " " || $0 == "\t" }
            guard !digits.isEmpty, digits.count <= 12, digits.allSatisfy(\.isASCII), let length = Int(digits),
                length >= 0
            else { throw .missingContentLength }
            guard length <= LSPFrame.maximumContentLength else { throw .contentTooLong(length) }
            return length
        }
        throw .missingContentLength
    }
}
