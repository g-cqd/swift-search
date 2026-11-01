internal import AemiJSON
internal import Foundation
internal import ReportSupport
internal import SwiftSearch

/// The standard output could not be written.
struct OutputError: Error, CustomStringConvertible {
    let description: String
}

/// Writes results to standard output in the format asked for.
struct Output {
    let format: FormatOptions.Format
    let presenter: PathPresenter?

    init(_ options: FormatOptions) {
        format = options.format
        presenter = options.relativeTo.map(PathPresenter.init(root:))
    }

    func path(_ path: String) -> String { presenter?.path(path) ?? path }

    func write(_ text: String) throws(OutputError) {
        do {
            try FileHandle.standardOutput.write(contentsOf: Data(text.utf8))
        } catch {
            throw OutputError(description: "the output could not be written: \(error)")
        }
    }

    func json(_ value: some Encodable) throws(OutputError) {
        var encoder = AemiJSON.JSONEncoder()
        encoder.prettyPrinted = true
        let bytes: [UInt8]
        do {
            bytes = try encoder.encodeToBytes(value)
        } catch {
            throw OutputError(description: "the report could not be encoded: \(error)")
        }
        try write(String(decoding: bytes, as: UTF8.self) + "\n")
    }

    /// The run's notes on standard error, unless quiet.
    static func notes(_ notes: [RunNote], quiet: Bool) {
        guard !quiet else { return }
        for note in notes { Diagnostics.note(note.message) }
    }

    // MARK: Text

    func text(_ record: MatchRecord) -> String {
        var line = "\(record.location): \(record.kind.rawValue) \(record.symbol)"
        if let signature = record.signature { line += " " + signature }
        line += " [\(record.access.rawValue)\(record.isStatic == true ? ", static" : "")]"
        var lines = [line]
        if let usr = record.usr { lines.append("    usr: \(usr)" + (record.module.map { " (\($0))" } ?? "")) }
        if let context = record.context { lines += text(context).map { "    " + $0 } }
        return lines.joined(separator: "\n")
    }

    private func text(_ context: SymbolContext) -> [String] {
        var lines: [String] = []
        if let documentation = context.documentation {
            lines += documentation.text.split(separator: "\n", omittingEmptySubsequences: false).map { "/// " + $0 }
        }
        if let scope = context.scope {
            lines.append("in \(scope.kind) \(scope.name) (lines \(scope.startLine)-\(scope.endLine))")
        }
        if let signature = context.signature { lines.append(signature) }
        let width = String(context.lines.last?.number ?? 0).count
        for line in context.lines {
            let number = String(line.number)
            lines.append(
                (line.isDeclaration ? ">" : " ") + String(repeating: " ", count: width - number.count) + number + " | "
                    + line.text)
        }
        if let body = context.body {
            lines += body.split(separator: "\n", omittingEmptySubsequences: false).map { "| " + $0 }
            if context.bodyIsTruncated { lines.append("| …") }
        }
        return lines
    }
}
