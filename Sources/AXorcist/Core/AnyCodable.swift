import Foundation
import CoreGraphics // Import for CGPoint, CGSize, CGRect
import Accessibility // Import for AXTextMarker, AXTextMarkerRange
import ApplicationServices // For AXUIElement
// It's likely AXorcist module, where this file lives, already imports Accessibility or AppKit,
// which would make AXTextMarker and AXTextMarkerRange available.
// If not, a more dynamic type check might be needed, or this file needs to import them.

// For encoding/decoding 'Any' type in JSON, especially for element attributes.
// Note: @unchecked Sendable is used because 'Any' cannot guarantee thread safety
public struct AnyCodable: Codable, @unchecked Sendable {
    public let value: Any

    public init<T>(_ value: T?) {
        self.value = value ?? ()
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let decodedValue = try AnyCodable.decodeValue(from: container) {
            self.value = decodedValue
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "AnyCodable value cannot be decoded"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        if try encodeValue(value, to: &container) {
            return
        }

        let context = EncodingError.Context(
            codingPath: container.codingPath,
            debugDescription: "AnyCodable value cannot be encoded"
        )
        throw EncodingError.invalidValue(value, context)
    }

    // MARK: - Private Helper Methods

    private static func decodeValue(from container: SingleValueDecodingContainer) throws -> Any? {
        if container.decodeNil() {
            return ()
        }

        // Try primitive types
        if let primitiveValue = try decodePrimitiveValue(from: container) {
            return primitiveValue
        }

        // Try collection types
        if let collectionValue = try decodeCollectionValue(from: container) {
            return collectionValue
        }

        return nil
    }

    private static func decodePrimitiveValue(from container: SingleValueDecodingContainer) throws -> Any? {
        if let bool = try? container.decode(Bool.self) { return bool }
        if let int = try? container.decode(Int.self) { return int }
        if let int32 = try? container.decode(Int32.self) { return int32 }
        if let int64 = try? container.decode(Int64.self) { return int64 }
        if let uint = try? container.decode(UInt.self) { return uint }
        if let uint32 = try? container.decode(UInt32.self) { return uint32 }
        if let uint64 = try? container.decode(UInt64.self) { return uint64 }
        if let double = try? container.decode(Double.self) { return double }
        if let float = try? container.decode(Float.self) { return float }
        if let string = try? container.decode(String.self) { return string }
        return nil
    }

    private static func decodeCollectionValue(from container: SingleValueDecodingContainer) throws -> Any? {
        if let array = try? container.decode([AnyCodable].self) {
            return array.map { $0.value }
        }
        if let dictionary = try? container.decode([String: AnyCodable].self) {
            return dictionary.mapValues { $0.value }
        }
        return nil
    }

    private func encodeValue(_ value: Any, to container: inout SingleValueEncodingContainer) throws -> Bool {
        switch value {
        case is Void:
            try container.encodeNil()
            return true
        case let primitiveValue:
            return try encodePrimitiveValue(primitiveValue, to: &container)
        }
    }

    private func encodePrimitiveValue(_ value: Any, to container: inout SingleValueEncodingContainer) throws -> Bool {
        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let int32 as Int32:
            try container.encode(Int(int32))
        case let int64 as Int64:
            try container.encode(int64)
        case let uint as UInt:
            try container.encode(uint)
        case let uint32 as UInt32:
            try container.encode(uint32)
        case let uint64 as UInt64:
            try container.encode(uint64)
        case let double as Double:
            try container.encode(double)
        case let float as Float:
            try container.encode(float)
        case let string as String:
            try container.encode(string)
        case let point as CGPoint:
            try container.encode(["x": point.x, "y": point.y])
        case let size as CGSize:
            try container.encode(["width": size.width, "height": size.height])
        case let url as NSURL:
            try container.encode(url.absoluteString)
        case let rect as CGRect:
            try container.encode(["x": rect.origin.x, "y": rect.origin.y, "width": rect.size.width, "height": rect.size.height])
        case let notif as AXNotification:
            // AXorcist: Handle AXNotification by encoding its raw string value.
            try container.encode(notif.rawValue)
        case let attrStr as NSAttributedString:
            // AXorcist: Handle NSAttributedString by encoding its string content.
            try container.encode(attrStr.string)
        case let element as Element:
            // AXorcist: Handle AXorcist 'Element' type by encoding its string description as a fallback.
            // Prefer specific serialization if a structured JSON representation is needed.
            try container.encode(String(describing: element))
        case let axEl as AXUIElement:
            // AXorcist: Handle CoreFoundation AXUIElement by encoding its string description as a fallback.
            // This avoids direct encoding of an opaque CFType.
            try container.encode(String(describing: axEl))
        case let val where String(describing: type(of: val)) == "__NSCFType":
            // Fallback for other __NSCFType instances (CoreFoundation types not explicitly handled).
            try container.encode(String(describing: val))
        case let array as [AnyCodable]:
            try container.encode(array)
        case let array as [Any?]:
            try container.encode(array.map { AnyCodable($0) })
        case let dictionary as [String: AnyCodable]:
            try container.encode(dictionary)
        case let dictionary as [String: Any?]:
            try container.encode(dictionary.mapValues { AnyCodable($0) })
        default:
            // DEBUG: Print the type of unhandled values
            print("AnyCodable unhandled type: \(String(describing: type(of: value))), value: \(String(describing: value))")
            return false
        }
        return true
    }
}
