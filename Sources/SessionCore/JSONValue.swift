import Foundation

/// A JSON value kept whole: a tool input has to be compared with a later one and, for a question,
/// sent back with the answers added.
public enum JSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    /// The number as written, so that nothing is lost by passing it through.
    case number(String)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    /// Wraps what `JSONSerialization` produced. Nil for anything that is not JSON.
    init?(_ value: Any) {
        switch value {
        case is NSNull:
            self = .null
        case let number as NSNumber:
            self = CFGetTypeID(number) == CFBooleanGetTypeID() ? .bool(number.boolValue) : .number(number.stringValue)
        case let string as String:
            self = .string(string)
        case let array as [Any]:
            self = .array(array.compactMap(JSONValue.init))
        case let object as [String: Any]:
            self = .object(object.compactMapValues(JSONValue.init))
        default:
            return nil
        }
    }

    public subscript(key: String) -> JSONValue? {
        if case .object(let members) = self { return members[key] }
        return nil
    }

    public var string: String? {
        if case .string(let string) = self { return string }
        return nil
    }

    var array: [JSONValue]? {
        if case .array(let array) = self { return array }
        return nil
    }

    /// Compact JSON with object keys in alphabetical order, so equal values read the same.
    public var serialized: String {
        switch self {
        case .null: return "null"
        case .bool(let bool): return bool ? "true" : "false"
        case .number(let number): return number
        case .string(let string): return Self.quoted(string)
        case .array(let array): return "[" + array.map(\.serialized).joined(separator: ",") + "]"
        case .object(let members):
            return "{" + members.sorted { $0.key < $1.key }
                .map { Self.quoted($0.key) + ":" + $0.value.serialized }
                .joined(separator: ",") + "}"
        }
    }

    static func quoted(_ string: String) -> String {
        var result = "\""
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            case _ where scalar.value < 0x20: result += String(format: "\\u%04x", scalar.value)
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result + "\""
    }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByBooleanLiteral,
    ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
}
