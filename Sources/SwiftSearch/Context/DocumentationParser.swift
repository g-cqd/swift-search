/// Reads a Swift documentation comment's summary and its `- Parameter`, `- Parameters:`, `- Returns:` and `- Throws:`
/// fields.
enum DocumentationParser {
    /// `lines` are the comment's lines without `///`, `/**` or `*/`.
    /// - Complexity: O(*n*) in the comment's length.
    static func parse(_ lines: [String]) -> SymbolContext.Documentation? {
        let text = lines.joined(separator: "\n").trimmingWhitespace()
        guard !text.isEmpty else { return nil }
        var summary: [String] = []
        var summaryDone = false
        var parameters: [String: String] = [:]
        var returns: String?
        var throwsText: String?
        var inParameterList = false
        for raw in lines {
            let line = raw.trimmingWhitespace()
            if line.isEmpty {
                if !summary.isEmpty { summaryDone = true }
                continue
            }
            guard line.hasPrefix("- ") else {
                if !summaryDone { summary.append(line) }
                continue
            }
            summaryDone = true
            let field = String(line.dropFirst(2))
            if let rest = field.dropPrefix("Parameters:") {
                inParameterList = true
                if !rest.isEmpty { summary.append(rest) }
            } else if let rest = field.dropPrefix("Parameter ") {
                inParameterList = false
                if let (name, description) = split(rest) { parameters[name] = description }
            } else if let rest = field.dropPrefix("Returns:") {
                inParameterList = false
                returns = rest
            } else if let rest = field.dropPrefix("Throws:") {
                inParameterList = false
                throwsText = rest
            } else if inParameterList, let (name, description) = split(field) {
                parameters[name] = description
            }
        }
        return SymbolContext.Documentation(
            summary: summary.isEmpty ? nil : summary.joined(separator: " "), parameters: parameters,
            returns: returns, throws: throwsText, text: text)
    }

    /// `name: description`.
    private static func split(_ text: String) -> (String, String)? {
        guard let colon = text.firstIndex(of: ":") else { return nil }
        let name = String(text[..<colon]).trimmingWhitespace()
        guard !name.isEmpty, !name.contains(" ") else { return nil }
        return (name, String(text[text.index(after: colon)...]).trimmingWhitespace())
    }
}

extension String {
    /// The rest of the string after `prefix`, trimmed; nil when it does not start with it.
    fileprivate func dropPrefix(_ prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)).trimmingWhitespace() : nil
    }
}
