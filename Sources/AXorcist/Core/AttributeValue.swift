// AttributeValue.swift - Strongly-typed replacement for AnyCodable in accessibility attributes

import Foundation

/// A type-safe enumeration for accessibility attribute values.
///
/// AttributeValue provides a strongly-typed alternative to AnyCodable for representing
/// the diverse value types found in accessibility attributes. It supports all common
/// types including strings, numbers, booleans, arrays, dictionaries, and null values.
///
/// ## Usage
///
/// ```swift
/// var attributes: [String: AttributeValue] = [:]
/// attributes["AXTitle"] = .string("My Window")
/// attributes["AXEnabled"] = .bool(true)
/// attributes["AXPosition"] = .dictionary(["x": .double(100), "y": .double(200)])
/// ```
public enum AttributeValue: Codable, Sendable, Equatable {
    case string(String)
    case bool(Bool)
    case int(Int)
    case double(Double)
    case array([AttributeValue])
    case dictionary([String: AttributeValue])
    case null

    // MARK: - Coding

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([AttributeValue].self) {
            self = .array(array)
        } else if let dictionary = try? container.decode([String: AttributeValue].self) {
            self = .dictionary(dictionary)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "AttributeValue cannot decode value")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .null:
            try container.encodeNil()
        case let .bool(value):
            try container.encode(value)
        case let .int(value):
            try container.encode(value)
        case let .double(value):
            try container.encode(value)
        case let .string(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case let .dictionary(value):
            try container.encode(value)
        }
    }
}

// MARK: - Value Extraction Helpers

extension AttributeValue {
    /// Extracts the string value if this is a string, otherwise returns nil
    public var stringValue: String? {
        if case let .string(value) = self { return value }
        return nil
    }

    /// Extracts the boolean value if this is a bool, otherwise returns nil
    public var boolValue: Bool? {
        if case let .bool(value) = self { return value }
        return nil
    }

    /// Extracts the integer value if this is an int, otherwise returns nil
    public var intValue: Int? {
        if case let .int(value) = self { return value }
        return nil
    }

    /// Extracts the double value if this is a double, otherwise returns nil
    public var doubleValue: Double? {
        if case let .double(value) = self { return value }
        return nil
    }

    /// Extracts the array value if this is an array, otherwise returns nil
    public var arrayValue: [AttributeValue]? {
        if case let .array(value) = self { return value }
        return nil
    }

    /// Extracts the dictionary value if this is a dictionary, otherwise returns nil
    public var dictionaryValue: [String: AttributeValue]? {
        if case let .dictionary(value) = self { return value }
        return nil
    }

    /// Returns true if this is a null value
    public var isNull: Bool {
        if case .null = self { return true }
        return false
    }
}

// MARK: - Convenience Initializers

extension AttributeValue {
    /// Creates an AttributeValue from any value, attempting to match the appropriate case
    public init(from value: Any?) {
        guard let value else {
            self = .null
            return
        }

        switch value {
        case let string as String:
            self = .string(string)
        case let bool as Bool:
            self = .bool(bool)
        case let int as Int:
            self = .int(int)
        case let double as Double:
            self = .double(double)
        case let array as [Any]:
            self = .array(array.map { AttributeValue(from: $0) })
        case let dictionary as [String: Any]:
            self = .dictionary(dictionary.mapValues { AttributeValue(from: $0) })
        default:
            if let nsNumber = value as? NSNumber {
                self = AttributeValue.fromNSNumber(nsNumber)
            } else if CFGetTypeID(value as CFTypeRef) == CFNullGetTypeID() {
                self = .null
            } else {
                // Fall back to string representation
                self = .string(String(describing: value))
            }
        }
    }

    /// Converts the AttributeValue back to its underlying Any representation
    public var anyValue: Any? {
        switch self {
        case .null:
            nil
        case let .string(value):
            value
        case let .bool(value):
            value
        case let .int(value):
            value
        case let .double(value):
            value
        case let .array(values):
            values.map(\.anyValue)
        case let .dictionary(dict):
            dict.mapValues { $0.anyValue }
        }
    }
}

// MARK: - CustomStringConvertible

extension AttributeValue: CustomStringConvertible {
    public var description: String {
        switch self {
        case .null:
            return "null"
        case let .string(value):
            return "\"\(value)\""
        case let .bool(value):
            return value ? "true" : "false"
        case let .int(value):
            return "\(value)"
        case let .double(value):
            return "\(value)"
        case let .array(values):
            let items = values.map(\.description).joined(separator: ", ")
            return "[\(items)]"
        case let .dictionary(dict):
            let items = dict.map { "\"\($0.key)\": \($0.value.description)" }.joined(separator: ", ")
            return "{\(items)}"
        }
    }
}

// MARK: - Migration Helper

extension AttributeValue {
    /// Creates an AttributeValue from an AnyCodable for migration purposes
    /// This will be removed once AnyCodable is fully eliminated
    public init(fromAnyCodable anyCodable: AnyCodable) {
        self.init(from: anyCodable.value)
    }
}

// MARK: - Private Helpers

extension AttributeValue {
    fileprivate static func fromNSNumber(_ number: NSNumber) -> AttributeValue {
        if number === kCFBooleanTrue as NSNumber {
            return .bool(true)
        }
        if number === kCFBooleanFalse as NSNumber {
            return .bool(false)
        }
        if number.doubleValue.truncatingRemainder(dividingBy: 1) == 0 {
            return .int(number.intValue)
        }
        return .double(number.doubleValue)
    }
}
