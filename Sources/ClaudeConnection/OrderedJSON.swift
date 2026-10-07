import Foundation

/// JSON that keeps object key order and number spelling, so that rewriting a user's settings file
/// changes only what was meant to change.
indirect enum OrderedJSON: Equatable {
    case object([Member])
    case array([OrderedJSON])
    case string(String)
    /// The number exactly as written in the source.
    case number(String)
    case bool(Bool)
    case null

    struct Member: Equatable {
        var key: String
        var value: OrderedJSON
    }

    subscript(key: String) -> OrderedJSON? {
        get {
            guard case .object(let members) = self else { return nil }
            return members.first { $0.key == key }?.value
        }
        set {
            guard case .object(var members) = self else { return }
            let index = members.firstIndex { $0.key == key }
            switch (index, newValue) {
            case (let index?, let value?): members[index].value = value
            case (let index?, nil): members.remove(at: index)
            case (nil, let value?): members.append(Member(key: key, value: value))
            case (nil, nil): break
            }
            self = .object(members)
        }
    }

    /// Equality that ignores the order of object members.
    func hasSameContent(as other: OrderedJSON) -> Bool {
        switch (self, other) {
        case (.object(let mine), .object(let theirs)):
            mine.count == theirs.count && mine.allSatisfy { member in
                other[member.key].map(member.value.hasSameContent) ?? false
            }
        case (.array(let mine), .array(let theirs)):
            mine.count == theirs.count && zip(mine, theirs).allSatisfy { $0.hasSameContent(as: $1) }
        default:
            self == other
        }
    }

    // MARK: Parsing

    struct ParseError: Error {}

    init(parsing data: Data) throws {
        var parser = Parser(bytes: Array(data))
        self = try parser.parseDocument()
    }

    private struct Parser {
        let bytes: [UInt8]
        var position = 0

        mutating func parseDocument() throws -> OrderedJSON {
            let value = try parseValue()
            skipWhitespace()
            guard position == bytes.count else { throw ParseError() }
            return value
        }

        private var current: UInt8? { position < bytes.count ? bytes[position] : nil }

        private mutating func skipWhitespace() {
            while let byte = current, byte == 0x20 || byte == 0x0A || byte == 0x0D || byte == 0x09 {
                position += 1
            }
        }

        private mutating func expect(_ byte: UInt8) throws {
            guard current == byte else { throw ParseError() }
            position += 1
        }

        private mutating func parseValue() throws -> OrderedJSON {
            skipWhitespace()
            switch current {
            case UInt8(ascii: "{"): return try parseObject()
            case UInt8(ascii: "["): return try parseArray()
            case UInt8(ascii: "\""): return .string(try parseString())
            case UInt8(ascii: "t"): try parseLiteral("true"); return .bool(true)
            case UInt8(ascii: "f"): try parseLiteral("false"); return .bool(false)
            case UInt8(ascii: "n"): try parseLiteral("null"); return .null
            default: return try parseNumber()
            }
        }

        private mutating func parseObject() throws -> OrderedJSON {
            try expect(UInt8(ascii: "{"))
            var members: [Member] = []
            skipWhitespace()
            if current == UInt8(ascii: "}") {
                position += 1
                return .object(members)
            }
            while true {
                skipWhitespace()
                let key = try parseString()
                skipWhitespace()
                try expect(UInt8(ascii: ":"))
                members.append(Member(key: key, value: try parseValue()))
                skipWhitespace()
                if current == UInt8(ascii: ",") {
                    position += 1
                } else {
                    try expect(UInt8(ascii: "}"))
                    return .object(members)
                }
            }
        }

        private mutating func parseArray() throws -> OrderedJSON {
            try expect(UInt8(ascii: "["))
            var elements: [OrderedJSON] = []
            skipWhitespace()
            if current == UInt8(ascii: "]") {
                position += 1
                return .array(elements)
            }
            while true {
                elements.append(try parseValue())
                skipWhitespace()
                if current == UInt8(ascii: ",") {
                    position += 1
                } else {
                    try expect(UInt8(ascii: "]"))
                    return .array(elements)
                }
            }
        }

        private mutating func parseLiteral(_ literal: String) throws {
            for byte in literal.utf8 { try expect(byte) }
        }

        private mutating func parseNumber() throws -> OrderedJSON {
            let start = position
            while let byte = current, "+-0123456789.eE".utf8.contains(byte) { position += 1 }
            let raw = String(decoding: bytes[start..<position], as: UTF8.self)
            guard Double(raw) != nil else { throw ParseError() }
            return .number(raw)
        }

        /// Strings are decoded by Foundation, which already knows every escape and surrogate rule.
        private mutating func parseString() throws -> String {
            let start = position
            try expect(UInt8(ascii: "\""))
            while let byte = current, byte != UInt8(ascii: "\"") {
                position += byte == UInt8(ascii: "\\") ? 2 : 1
            }
            try expect(UInt8(ascii: "\""))
            guard position <= bytes.count,
                  let string = try? JSONDecoder().decode(String.self, from: Data(bytes[start..<position]))
            else { throw ParseError() }
            return string
        }
    }

    // MARK: Serialising

    /// One member or element per line, each level indented by `indentation`.
    func serialized(indentation: String) -> String {
        var output = ""
        write(to: &output, indentation: indentation, depth: 0)
        return output
    }

    private func write(to output: inout String, indentation: String, depth: Int) {
        let pad = String(repeating: indentation, count: depth + 1)
        let closingPad = String(repeating: indentation, count: depth)
        switch self {
        case .object(let members) where members.isEmpty: output += "{}"
        case .array(let elements) where elements.isEmpty: output += "[]"
        case .object(let members):
            output += "{\n"
            for (index, member) in members.enumerated() {
                output += pad + Self.quoted(member.key) + ": "
                member.value.write(to: &output, indentation: indentation, depth: depth + 1)
                output += index == members.count - 1 ? "\n" : ",\n"
            }
            output += closingPad + "}"
        case .array(let elements):
            output += "[\n"
            for (index, element) in elements.enumerated() {
                output += pad
                element.write(to: &output, indentation: indentation, depth: depth + 1)
                output += index == elements.count - 1 ? "\n" : ",\n"
            }
            output += closingPad + "]"
        case .string(let string): output += Self.quoted(string)
        case .number(let raw): output += raw
        case .bool(let bool): output += bool ? "true" : "false"
        case .null: output += "null"
        }
    }

    private static func quoted(_ string: String) -> String {
        var output = "\""
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\"": output += "\\\""
            case "\\": output += "\\\\"
            case "\n": output += "\\n"
            case "\r": output += "\\r"
            case "\t": output += "\\t"
            case _ where scalar.value < 0x20: output += String(format: "\\u%04x", scalar.value)
            default: output.unicodeScalars.append(scalar)
            }
        }
        return output + "\""
    }
}
