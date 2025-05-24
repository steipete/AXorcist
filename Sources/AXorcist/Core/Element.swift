// Element.swift - Wrapper for AXUIElement for a more Swift-idiomatic interface

import ApplicationServices // For AXUIElement and other C APIs
import Foundation
// GlobalAXLogger is now expected to be imported if this file is part of AXorcistLib, or accessible if in the same target.
// Assuming AXorcistLib is a separate module, you'd need:
// import AXorcistLib // If GlobalAXLogger is in AXorcistLib and this file is in AXorcist module.

// The AXORC_JSON_LOG_ENABLED and related fputs can be removed as GlobalAXLogger manages its state.

// Element struct is NOT @MainActor. Isolation is applied to members that need it.
public struct Element: Equatable, Hashable {
    public let underlyingElement: AXUIElement

    // Stored properties for pre-fetched data, especially for AXpector
    public var attributes: [String: AnyCodable]? // Populated by deep queries
    public var prefetchedChildren: [Element]? // Populated by deep queries. Renamed from 'children'.
    public var actions: [String]? // Populated by deep queries

    // Initializer for basic wrapping
    public init(_ element: AXUIElement) {
        self.underlyingElement = element
        self.attributes = nil // Not fetched by default with this initializer
        self.prefetchedChildren = nil // Not fetched by default. Renamed from 'children'.
        self.actions = nil // Not fetched by default
    }

    // Initializer for use by AXorcist when creating fully populated elements (e.g., from a tree fetch)
    public init(_ element: AXUIElement, attributes: [String: AnyCodable]?, children: [Element]?, actions: [String]?) {
        self.underlyingElement = element
        self.attributes = attributes
        self.prefetchedChildren = children // Renamed from 'children'.
        self.actions = actions
    }

    // Implement Equatable - no longer needs nonisolated as struct is not @MainActor
    public static func == (lhs: Element, rhs: Element) -> Bool {
        return CFEqual(lhs.underlyingElement, rhs.underlyingElement)
    }

    // Implement Hashable - no longer needs nonisolated
    public func hash(into hasher: inout Hasher) {
        hasher.combine(CFHash(underlyingElement))
    }

    // Generic method to get an attribute's value (converted to Swift type T)
    // Now tries to read from stored attributes first, then fetches if not available.
    @MainActor
    public func attribute<T>(_ attribute: Attribute<T>) -> T? {
        // Try to get from pre-fetched attributes first
        if let storedValue = getStoredAttribute(attribute) {
            return storedValue
        }

        axDebugLog("'\(attribute.rawValue)' not in stored. Fetching...")

        if T.self == [AXUIElement].self {
            return fetchAXUIElementArray(attribute)
        } else {
            return fetchAndConvertAttribute(attribute)
        }
    }

    @MainActor
    private func getStoredAttribute<T>(_ attribute: Attribute<T>) -> T? {
        guard let storedAttributes = self.attributes,
              let anyCodableValue = storedAttributes[attribute.rawValue] else {
            return nil
        }

        axDebugLog("Found '\(attribute.rawValue)' in stored attributes.")

        // Attempt to convert AnyCodable to T
        if T.self == String.self, let strValue = anyCodableValue.value as? String { return strValue as? T }
        if T.self == Bool.self, let boolValue = anyCodableValue.value as? Bool { return boolValue as? T }
        if T.self == Int.self, let intValue = anyCodableValue.value as? Int { return intValue as? T }
        if T.self == [Element].self, let elementArray = anyCodableValue.value as? [Element] { return elementArray as? T }
        if T.self == AXUIElement.self,
           let cfValue = anyCodableValue.value as CFTypeRef?,
           CFGetTypeID(cfValue) == AXUIElementGetTypeID() {
            return cfValue as? T
        }

        if let val = anyCodableValue.value as? T {
            return val
        } else {
            axDebugLog("Stored attribute '\(attribute.rawValue)' (type \(type(of: anyCodableValue.value))) could not be cast to \(String(describing: T.self))")
            return nil
        }
    }

    @MainActor
    private func fetchAXUIElementArray<T>(_ attribute: Attribute<T>) -> T? {
        axDebugLog("Special handling for T == [AXUIElement]. Attribute: \(attribute.rawValue)")
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(self.underlyingElement, attribute.rawValue as CFString, &value)

        guard error == .success else {
            if error == .noValue {
                axDebugLog("Attribute '\(attribute.rawValue)' has no value.")
            } else {
                axDebugLog("Error fetching '\(attribute.rawValue)': \(error.rawValue)")
            }
            return nil
        }

        if let cfArray = value, CFGetTypeID(cfArray) == CFArrayGetTypeID() {
            if let axElements = cfArray as? [AXUIElement] {
                axDebugLog("Successfully fetched and cast \(axElements.count) AXUIElements for '\(attribute.rawValue)'.")
                return axElements as? T
            } else {
                axDebugLog("CFArray for '\(attribute.rawValue)' failed to cast to [AXUIElement].")
            }
        } else if value != nil {
            axDebugLog("Value for '\(attribute.rawValue)' was not a CFArray. TypeID: \(String(describing: CFGetTypeID(value!)))")
        } else {
            axDebugLog("Value for '\(attribute.rawValue)' was nil despite .success.")
        }
        return nil
    }

    @MainActor
    private func fetchAndConvertAttribute<T>(_ attribute: Attribute<T>) -> T? {
        axDebugLog("Using basic CFTypeRef conversion for T = \(String(describing: T.self)), Attribute: \(attribute.rawValue).")
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(self.underlyingElement, attribute.rawValue as CFString, &value)

        if error != .success {
            if error != .noValue {
                axDebugLog("Error \(error.rawValue) fetching '\(attribute.rawValue)' for basic conversion.")
            }
            return nil
        }

        guard let unwrappedCFValue = value else {
            axDebugLog("Value was nil for '\(attribute.rawValue)' after fetch for basic conversion.")
            return nil
        }

        return convertCFTypeToSwiftType(unwrappedCFValue, attribute: attribute)
    }

    @MainActor
    private func convertCFTypeToSwiftType<T>(_ cfValue: CFTypeRef, attribute: Attribute<T>) -> T? {
        // Perform basic conversions
        if T.self == String.self {
            if CFGetTypeID(cfValue) == CFStringGetTypeID() {
                return ((cfValue as! CFString) as String as? T)
            } else if CFGetTypeID(cfValue) == CFAttributedStringGetTypeID() { // Handle AttributedString
                return ((cfValue as! NSAttributedString).string as? T)
            }
        } else if T.self == Bool.self {
            if CFGetTypeID(cfValue) == CFBooleanGetTypeID() {
                return (CFBooleanGetValue((cfValue as! CFBoolean)) as? T)
            }
        } else if T.self == Int.self {
            if CFGetTypeID(cfValue) == CFNumberGetTypeID() {
                var intValue: Int = 0
                if CFNumberGetValue((cfValue as! CFNumber), .sInt64Type, &intValue) {
                    return (intValue as? T)
                }
            }
        } else if T.self == AXUIElement.self {
            if CFGetTypeID(cfValue) == AXUIElementGetTypeID() {
                return cfValue as? T
            }
        }

        // If it's 'Any' or other complex types, ValueUnwrapper might be appropriate.
        if T.self == Any.self || T.self == AnyObject.self { // If T is Any, try ValueUnwrapper
            axDebugLog("Attribute \(attribute.rawValue): T is Any/AnyObject. Using ValueUnwrapper.")
            return ValueUnwrapper.unwrap(cfValue) as? T
        }

        if let directCast = cfValue as? T {
            axDebugLog("Basic conversion succeeded with direct cast for T = \(String(describing: T.self)), Attribute: \(attribute.rawValue).")
            return directCast
        }

        axDebugLog("Attempting ValueUnwrapper for T = \(String(describing: T.self)), Attribute: \(attribute.rawValue).")
        if let valueFromUnwrapper = ValueUnwrapper.unwrap(cfValue) as? T {
            return valueFromUnwrapper
        }

        let warningMessage = "Basic conversion and ValueUnwrapper FAILED for T = \(String(describing: T.self)), "
        let warningDetail = "Attribute: \(attribute.rawValue). Value type: \(String(describing: CFGetTypeID(cfValue)))"
        axWarningLog(warningMessage + warningDetail)
        return nil
    }

    // Method to get the raw CFTypeRef? for an attribute
    // This is useful for functions like attributesMatch that do their own CFTypeID checking.
    // This also needs to be @MainActor as AXUIElementCopyAttributeValue should be on main thread.
    @MainActor
    public func rawAttributeValue(named attributeName: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(self.underlyingElement, attributeName as CFString, &value)
        if error == .success {
            return value // Caller is responsible for CFRelease if this is not ARC-managed (it should be with Swift)
        } else if error == .attributeUnsupported {
            axDebugLog("Attribute \(attributeName) unsupported for element.") // Removed self.underlyingElement for brevity, context is clear
        } else if error == .noValue {
            axDebugLog("Attribute \(attributeName) has no value for element.")
        } else {
            axDebugLog("Error getting attribute \(attributeName) for element: \(error.rawValue)")
        }
        return nil
    }

    // Remaining properties and methods will stay here for now
    // (e.g., children, parameterizedAttribute, briefDescription, generatePathString, static factories)
    // Action methods have been moved to Element+Actions.swift

    // @MainActor public var children: [Element]? { ... }

    // @MainActor
    // public func generatePathString() -> String { ... }

    // MARK: - Attribute Settability Check
    @MainActor
    public func isAttributeSettable(named attributeName: String) -> Bool {
        var isSettable: DarwinBoolean = false
        let error = AXUIElementIsAttributeSettable(self.underlyingElement, attributeName as CFString, &isSettable)
        if error == .success {
            return isSettable.boolValue
        }
        // Log error or handle appropriately
        axDebugLog("Error checking if attribute \(attributeName) is settable: \(error.rawValue)")
        return false
    }

    // MARK: - Attribute Accessors (Raw and Typed)

    // ... existing attribute accessors ...

    // MARK: - Computed Properties for Common Attributes & Heuristics

    // ... existing properties like role, title, isEnabled ...

    /// A computed name for the element, derived from common attributes like title, value, description, etc.
    /// This provides a general-purpose, human-readable name.
    @MainActor
    public func computedName() -> String? {
        if let titleStr = self.title(), !titleStr.isEmpty, titleStr != AXMiscConstants.kAXNotAvailableString { return titleStr }

        if let valueAny = self.value(), let valueStr = valueAny as? String, !valueStr.isEmpty, valueStr != AXMiscConstants.kAXNotAvailableString { return valueStr }

        if let descStr = self.descriptionText(), !descStr.isEmpty, descStr != AXMiscConstants.kAXNotAvailableString { return descStr }

        if let helpStr: String = self.attribute(Attribute(AXAttributeNames.kAXHelpAttribute)), !helpStr.isEmpty, helpStr != AXMiscConstants.kAXNotAvailableString { return helpStr }
        if let phValueStr: String = self.attribute(Attribute(AXAttributeNames.kAXPlaceholderValueAttribute)),
           !phValueStr.isEmpty, phValueStr != AXMiscConstants.kAXNotAvailableString { return phValueStr }

        let roleNameStr: String = self.role() ?? "Element"

        if let roleDescStr = self.roleDescription(), !roleDescStr.isEmpty, roleDescStr != AXMiscConstants.kAXNotAvailableString {
            return "\(roleDescStr) (\(roleNameStr))"
        }
        axDebugLog("computedName: Could not determine a descriptive name.")
        return nil
    }

    // MARK: - Path and Hierarchy

    @MainActor
    public func getValueType(forAttribute attributeName: String) -> AXAttributeValueType {
        var cfValue: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(self.underlyingElement, attributeName as CFString, &cfValue)

        if error == .noValue {
            axDebugLog("Attribute '\(attributeName)' has no value.")
            return .noValue
        }

        guard error == .success, let value = cfValue else {
            axDebugLog("Error fetching attribute '\(attributeName)': \(error.rawValue)")
            return .error
        }

        let typeID = CFGetTypeID(value)

        if typeID == AXUIElementGetTypeID() {
            return .axElement
        } else if typeID == CFArrayGetTypeID() {
            let array = value as! CFArray // Safe cast due to typeID check
            if CFArrayGetCount(array) > 0 {
                let firstElementPtr = CFArrayGetValueAtIndex(array, 0) // Returns UnsafeRawPointer
                let firstElementTypeID = CFGetTypeID(firstElementPtr as CFTypeRef?)

                if firstElementTypeID == AXUIElementGetTypeID() {
                    return .axElementArray
                } else {
                    // Could be an array of other CFType, e.g., CFString, CFNumber
                    // For simplicity, classify as .array and let ValueUnwrapper handle specifics if needed elsewhere.
                    axDebugLog("Attribute '\(attributeName)' is an array, first element type ID: \(firstElementTypeID)")
                    return .array // Generic array type
                }
            } else {
                return .emptyArray // Empty array
            }
        } else if typeID == CFBooleanGetTypeID() {
            return .boolean
        } else if typeID == CFNumberGetTypeID() {
            return .number
        } else if typeID == CFStringGetTypeID() {
            return .string
        } else if typeID == CFAttributedStringGetTypeID() {
            return .attributedString
        } else if typeID == AXValueGetTypeID() {
            // Further inspect AXValue to determine its specific type (e.g., CGPoint, CGSize, CGRect, CFRange)
            let axValue = value as! AXValue // Force cast since we already checked the typeID
            let valueTypeEnum = AXValueGetType(axValue)
            switch valueTypeEnum {
            case .cgPoint: return .point
            case .cgSize: return .size
            case .cgRect: return .rect
            case .cfRange: return .range
            default:
                axDebugLog("Unhandled AXValueType: \(valueTypeEnum.rawValue) for attribute '\(attributeName)'")
                return .unknown // Other AXValue types not specifically handled
            }
        }

        axDebugLog("Attribute '\(attributeName)' has an unknown or unhandled CFTypeID: \(typeID)")
        return .unknown
    }
}
