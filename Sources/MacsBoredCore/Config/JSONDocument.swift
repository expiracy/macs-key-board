import Foundation

/// A JSON value with its object keys in the order they were written, so a file read and written back
/// keeps its shape, and fields MacsBored doesn't know survive untouched.
public indirect enum JSONValue: Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([(String, JSONValue)])

    public static func == (lhs: JSONValue, rhs: JSONValue) -> Bool {
        switch (lhs, rhs) {
        case (.null, .null): return true
        case let (.bool(a), .bool(b)): return a == b
        case let (.number(a), .number(b)): return a == b
        case let (.string(a), .string(b)): return a == b
        case let (.array(a), .array(b)): return a == b
        case let (.object(a), .object(b)):
            return a.count == b.count && zip(a, b).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
        default: return false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .null: hasher.combine(0)
        case let .bool(b): hasher.combine(b)
        case let .number(n): hasher.combine(n)
        case let .string(s): hasher.combine(s)
        case let .array(items): hasher.combine(items)
        case let .object(members):
            for (key, value) in members { hasher.combine(key); hasher.combine(value) }
        }
    }

    var isScalar: Bool {
        switch self {
        case .array, .object: false
        default: true
        }
    }
}

/// A value read from a file, with the line it starts on, for messages that point at the mistake.
public struct JSONNode: Sendable {
    public struct Member: Sendable {
        public let key: String
        public let node: JSONNode
    }

    public enum Kind: Sendable {
        case null, bool(Bool), number(Double), string(String)
        case array([JSONNode])
        case object([Member])
    }

    public let line: Int
    public let kind: Kind

    public var value: JSONValue {
        switch kind {
        case .null: .null
        case let .bool(b): .bool(b)
        case let .number(n): .number(n)
        case let .string(s): .string(s)
        case let .array(items): .array(items.map(\.value))
        case let .object(members): .object(members.map { ($0.key, $0.node.value) })
        }
    }

    public var object: [Member]? {
        if case let .object(members) = kind { return members }
        return nil
    }

    public var array: [JSONNode]? {
        if case let .array(items) = kind { return items }
        return nil
    }

    public var string: String? {
        if case let .string(s) = kind { return s }
        return nil
    }

    public var bool: Bool? {
        if case let .bool(b) = kind { return b }
        return nil
    }

    public var isNull: Bool {
        if case .null = kind { return true }
        return false
    }

    public subscript(key: String) -> JSONNode? {
        object?.first { $0.key == key }?.node
    }

    /// The whole of `text` as one JSON value.
    public static func parse(_ text: String) throws -> JSONNode {
        try parse(Data(text.utf8))
    }

    public static func parse(_ data: Data) throws -> JSONNode {
        var parser = JSONParser(bytes: Array(data))
        return try parser.document()
    }
}

/// Why a file isn't JSON, and where.
public struct JSONParseError: Error, Equatable, Sendable, CustomStringConvertible {
    public let line: Int
    public let message: String
    public var description: String { "Line \(line): \(message)" }
}

private struct JSONParser {
    let bytes: [UInt8]
    var index = 0
    var line = 1

    init(bytes: [UInt8]) {
        // A byte-order mark is not part of the value.
        self.bytes = bytes.starts(with: [0xEF, 0xBB, 0xBF]) ? Array(bytes.dropFirst(3)) : bytes
    }

    mutating func document() throws -> JSONNode {
        skipSpace()
        guard index < bytes.count else { throw fail("The file is empty.") }
        let node = try value()
        skipSpace()
        guard index == bytes.count else { throw fail("Something follows the end of the settings.") }
        return node
    }

    func fail(_ message: String) -> JSONParseError { JSONParseError(line: line, message: message) }

    mutating func skipSpace() {
        while index < bytes.count {
            switch bytes[index] {
            case 0x0A: line += 1; index += 1
            case 0x20, 0x09, 0x0D: index += 1
            default: return
            }
        }
    }

    mutating func value() throws -> JSONNode {
        skipSpace()
        guard index < bytes.count else { throw fail("The file ends too soon.") }
        let start = line
        switch bytes[index] {
        case UInt8(ascii: "{"): return JSONNode(line: start, kind: .object(try members()))
        case UInt8(ascii: "["): return JSONNode(line: start, kind: .array(try items()))
        case UInt8(ascii: "\""): return JSONNode(line: start, kind: .string(try string()))
        case UInt8(ascii: "t"): try word("true"); return JSONNode(line: start, kind: .bool(true))
        case UInt8(ascii: "f"): try word("false"); return JSONNode(line: start, kind: .bool(false))
        case UInt8(ascii: "n"): try word("null"); return JSONNode(line: start, kind: .null)
        case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"): return JSONNode(line: start, kind: .number(try number()))
        default: throw fail("Expected a value: a string in \"quotes\", a number, true, false, null, [ or {.")
        }
    }

    mutating func word(_ word: String) throws {
        let expected = Array(word.utf8)
        guard bytes.count - index >= expected.count, Array(bytes[index..<index + expected.count]) == expected else {
            throw fail("Expected a value. Did you mean \(word)? Text values need \"quotes\".")
        }
        index += expected.count
    }

    mutating func number() throws -> Double {
        let start = index
        while index < bytes.count, "+-0123456789.eE".utf8.contains(bytes[index]) { index += 1 }
        guard let text = String(bytes: bytes[start..<index], encoding: .utf8), let number = Double(text) else {
            throw fail("This isn't a number.")
        }
        return number
    }

    mutating func string() throws -> String {
        index += 1
        var out = [UInt8]()
        while true {
            guard index < bytes.count else { throw fail("A text value is missing its closing quote.") }
            let byte = bytes[index]
            index += 1
            switch byte {
            case UInt8(ascii: "\""):
                return String(decoding: out, as: UTF8.self)
            case 0x0A:
                throw fail("A text value is missing its closing quote.")
            case UInt8(ascii: "\\"):
                guard index < bytes.count else { throw fail("A text value ends with a lone backslash.") }
                let escape = bytes[index]
                index += 1
                switch escape {
                case UInt8(ascii: "\""): out.append(0x22)
                case UInt8(ascii: "\\"): out.append(0x5C)
                case UInt8(ascii: "/"): out.append(0x2F)
                case UInt8(ascii: "b"): out.append(0x08)
                case UInt8(ascii: "f"): out.append(0x0C)
                case UInt8(ascii: "n"): out.append(0x0A)
                case UInt8(ascii: "r"): out.append(0x0D)
                case UInt8(ascii: "t"): out.append(0x09)
                case UInt8(ascii: "u"):
                    var scalar = try hex4()
                    if (0xD800...0xDBFF).contains(scalar), index + 1 < bytes.count,
                       bytes[index] == UInt8(ascii: "\\"), bytes[index + 1] == UInt8(ascii: "u") {
                        index += 2
                        let low = try hex4()
                        scalar = 0x10000 + ((scalar - 0xD800) << 10) + (low - 0xDC00)
                    }
                    guard let unicode = Unicode.Scalar(scalar) else { throw fail("A \\u escape isn't a character.") }
                    out.append(contentsOf: Array(String(Character(unicode)).utf8))
                default:
                    throw fail("A backslash in text must be followed by \", \\, /, b, f, n, r, t or u.")
                }
            default:
                out.append(byte)
            }
        }
    }

    mutating func hex4() throws -> UInt32 {
        guard bytes.count - index >= 4, let text = String(bytes: bytes[index..<index + 4], encoding: .utf8),
              let value = UInt32(text, radix: 16) else { throw fail("A \\u escape needs four hex digits.") }
        index += 4
        return value
    }

    mutating func items() throws -> [JSONNode] {
        index += 1
        var items: [JSONNode] = []
        skipSpace()
        if index < bytes.count, bytes[index] == UInt8(ascii: "]") { index += 1; return items }
        while true {
            items.append(try value())
            skipSpace()
            guard index < bytes.count else { throw fail("A list is missing its closing ].") }
            if bytes[index] == UInt8(ascii: ",") {
                index += 1
                skipSpace()
                if index < bytes.count, bytes[index] == UInt8(ascii: "]") { throw fail("A list has a comma after its last item.") }
                continue
            }
            if bytes[index] == UInt8(ascii: "]") { index += 1; return items }
            throw fail("Expected a comma or ] in a list.")
        }
    }

    mutating func members() throws -> [JSONNode.Member] {
        index += 1
        var members: [JSONNode.Member] = []
        skipSpace()
        if index < bytes.count, bytes[index] == UInt8(ascii: "}") { index += 1; return members }
        while true {
            skipSpace()
            guard index < bytes.count, bytes[index] == UInt8(ascii: "\"") else {
                if index < bytes.count, bytes[index] == UInt8(ascii: "}") { throw fail("There's a comma after the last field.") }
                throw fail("Expected a field name in \"quotes\".")
            }
            let key = try string()
            skipSpace()
            guard index < bytes.count, bytes[index] == UInt8(ascii: ":") else { throw fail("Expected : after \"\(key)\".") }
            index += 1
            members.append(JSONNode.Member(key: key, node: try value()))
            skipSpace()
            guard index < bytes.count else { throw fail("An object is missing its closing }.") }
            if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
            if bytes[index] == UInt8(ascii: "}") { index += 1; return members }
            throw fail("Expected a comma or } after \"\(key)\".")
        }
    }
}

// MARK: - Writing

extension JSONValue {
    /// Two-space indents; a list of plain values, or an object of up to three plain values, on one
    /// line when it fits. Ends with a newline.
    public func written() -> String {
        var out = ""
        write(into: &out, indent: 0)
        return out + "\n"
    }

    private static let lineLimit = 100

    private func write(into out: inout String, indent: Int) {
        if let inline = inlineForm(), indent * 2 + inline.count <= Self.lineLimit {
            out += inline
            return
        }
        let pad = String(repeating: "  ", count: indent + 1)
        let close = String(repeating: "  ", count: indent)
        switch self {
        case let .array(items):
            out += "[\n"
            for (i, item) in items.enumerated() {
                out += pad
                item.write(into: &out, indent: indent + 1)
                out += i < items.count - 1 ? ",\n" : "\n"
            }
            out += close + "]"
        case let .object(members):
            out += "{\n"
            for (i, member) in members.enumerated() {
                out += pad + Self.quoted(member.0) + ": "
                member.1.write(into: &out, indent: indent + 1)
                out += i < members.count - 1 ? ",\n" : "\n"
            }
            out += close + "}"
        default:
            out += scalarForm
        }
    }

    private func inlineForm() -> String? {
        switch self {
        case let .array(items):
            guard items.allSatisfy(\.isScalar) else { return nil }
            return "[" + items.map(\.scalarForm).joined(separator: ", ") + "]"
        case let .object(members):
            if members.isEmpty { return "{}" }
            guard members.count <= 3, members.allSatisfy({ $0.1.isScalar }) else { return nil }
            return "{ " + members.map { Self.quoted($0.0) + ": " + $0.1.scalarForm }.joined(separator: ", ") + " }"
        default:
            return scalarForm
        }
    }

    private var scalarForm: String {
        switch self {
        case .null: return "null"
        case let .bool(b): return b ? "true" : "false"
        case let .number(n):
            if n.rounded() == n, abs(n) < 1e15 { return String(Int64(n)) }
            return String(n)
        case let .string(s): return Self.quoted(s)
        default: return ""
        }
    }

    static func quoted(_ text: String) -> String {
        var out = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case _ where scalar.value < 0x20: out += String(format: "\\u%04x", scalar.value)
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }
}

/// Fields of an entry that MacsBored doesn't know, in the order they were written, kept so writing
/// the file back never loses them.
public struct JSONFields: Hashable, Sendable {
    public var members: [(String, JSONValue)]

    public init(_ members: [(String, JSONValue)] = []) { self.members = members }

    public var isEmpty: Bool { members.isEmpty }

    public static func == (lhs: JSONFields, rhs: JSONFields) -> Bool {
        JSONValue.object(lhs.members) == JSONValue.object(rhs.members)
    }

    public func hash(into hasher: inout Hasher) { hasher.combine(JSONValue.object(members)) }
}
