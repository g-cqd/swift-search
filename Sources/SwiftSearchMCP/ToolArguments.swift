internal import AemiJSON
internal import SwiftSearch

/// Why a tool's arguments were refused; the client sees the message as a tool error.
struct ArgumentError: Error, Sendable, Equatable {
    let message: String
}

/// Typed, checked reads of a tool's `arguments` object.
struct ToolArguments: Sendable {
    let json: JSON

    func string(_ key: String) throws(ArgumentError) -> String? {
        let value = json[key]
        guard value.exists, !value.isNull else { return nil }
        guard let string = value.string else { throw ArgumentError(message: "'\(key)' must be a string") }
        return string
    }

    func requiredString(_ key: String) throws(ArgumentError) -> String {
        guard let value = try string(key), !value.isEmpty else {
            throw ArgumentError(message: "'\(key)' is required")
        }
        return value
    }

    func bool(_ key: String) throws(ArgumentError) -> Bool? {
        let value = json[key]
        guard value.exists, !value.isNull else { return nil }
        guard let bool = value.bool else { throw ArgumentError(message: "'\(key)' must be a boolean") }
        return bool
    }

    /// An integer in `range`.
    func integer(_ key: String, in range: ClosedRange<Int>) throws(ArgumentError) -> Int? {
        let value = json[key]
        guard value.exists, !value.isNull else { return nil }
        guard let number = value.int, range.contains(number) else {
            throw ArgumentError(message: "'\(key)' must be an integer in \(range.lowerBound)...\(range.upperBound)")
        }
        return number
    }

    /// A string or an array of strings, as an array; at most `limit` entries.
    func strings(_ key: String, limit: Int = 256) throws(ArgumentError) -> [String] {
        let value = json[key]
        guard value.exists, !value.isNull else { return [] }
        if let single = value.string { return [single] }
        guard value.isArray, value.count <= limit else {
            throw ArgumentError(message: "'\(key)' must be a string or an array of at most \(limit) strings")
        }
        var strings: [String] = []
        for element in value.arrayValue {
            guard let string = element.string else {
                throw ArgumentError(message: "'\(key)' must contain strings only")
            }
            strings.append(string)
        }
        return strings
    }

    /// Values of a raw-value enum, named by a string or an array of strings.
    func values<Value: RawRepresentable & CaseIterable & Hashable>(_ key: String, of type: Value.Type)
        throws(ArgumentError)
        -> Set<Value>
    where Value.RawValue == String {
        var values: Set<Value> = []
        for name in try strings(key) {
            guard let value = Value(rawValue: name) else {
                let known = Value.allCases.map(\.rawValue).joined(separator: ", ")
                throw ArgumentError(message: "'\(key)': '\(name)' is not one of \(known)")
            }
            values.insert(value)
        }
        return values
    }
}
