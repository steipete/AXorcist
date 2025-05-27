// Element.swift - Wrapper for AXUIElement for a more Swift-idiomatic interface

import AppKit // Added to provide NSRunningApplication and NSWorkspace
import ApplicationServices // For AXUIElement and other C APIs
import Foundation

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

    // Implement Equatable
    public static func == (lhs: Element, rhs: Element) -> Bool {
        return CFEqual(lhs.underlyingElement, rhs.underlyingElement)
    }

    // Implement Hashable
    public func hash(into hasher: inout Hasher) {
        hasher.combine(CFHash(underlyingElement))
    }

    // Generic method to get an attribute's value (converted to Swift type T)
    @MainActor
    public func attribute<T>(_ attribute: Attribute<T>) -> T? {
        // Try to get from pre-fetched attributes first
        if let storedValue = getStoredAttribute(attribute) {
            return storedValue
        }

        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "'\\(attribute.rawValue)' not in stored. Fetching..."))

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

        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "Found '\\(attribute.rawValue)' in stored attributes."))

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
            GlobalAXLogger.shared.log(AXLogEntry(
                level: .debug,
                message: "Stored attribute '\\(attribute.rawValue)' " +
                    "(type \\(type(of: anyCodableValue.value))) " +
                    "could not be cast to \\(String(describing: T.self))"
            ))
            return nil
        }
    }

    @MainActor
    private func fetchAXUIElementArray<T>(_ attribute: Attribute<T>) -> T? {
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "Special handling for T == [AXUIElement]. Attribute: \\(attribute.rawValue)"))
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(self.underlyingElement, attribute.rawValue as CFString, &value)

        guard error == .success else {
            if error == .noValue {
                GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "Attribute '\\(attribute.rawValue)' has no value."))
            } else {
                GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "Error fetching '\\(attribute.rawValue)': \\(error.rawValue)"))
            }
            return nil
        }

        if let cfArray = value, CFGetTypeID(cfArray) == CFArrayGetTypeID() {
            if let axElements = cfArray as? [AXUIElement] {
                GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "Successfully fetched and cast \\(axElements.count) AXUIElements for '\\(attribute.rawValue)'."))
                return axElements as? T
            } else {
                GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "CFArray for '\\(attribute.rawValue)' failed to cast to [AXUIElement]."))
            }
        } else if value != nil {
            GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "Value for '\\(attribute.rawValue)' was not a CFArray. TypeID: \\(String(describing: CFGetTypeID(value!)))"))
        } else {
            GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "Value for '\\(attribute.rawValue)' was nil despite .success."))
        }
        return nil
    }

    @MainActor
    private func fetchAndConvertAttribute<T>(_ attribute: Attribute<T>) -> T? {
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "Using basic CFTypeRef conversion for T = \\(String(describing: T.self)), Attribute: \\(attribute.rawValue)."))
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(self.underlyingElement, attribute.rawValue as CFString, &value)

        if error != .success {
            if error != .noValue {
                GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "Error \\(error.rawValue) fetching '\\(attribute.rawValue)' for basic conversion."))
            }
            return nil
        }

        guard let unwrappedCFValue = value else {
            GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "Value was nil for '\\(attribute.rawValue)' after fetch for basic conversion."))
            return nil
        }

        // Use the type conversion functionality from Element+TypeConversion.swift
        return convertCFTypeToSwiftType(unwrappedCFValue, attribute: attribute)
    }

    @MainActor
    public func rawAttributeValue(named attributeName: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(self.underlyingElement, attributeName as CFString, &value)
        if error == .success {
            return value
        } else if error == .attributeUnsupported {
            GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "Attribute \\(attributeName) unsupported for element."))
        } else if error == .noValue {
            GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "Attribute \\(attributeName) has no value for element."))
        } else {
            GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "Error getting attribute \\(attributeName) for element: \\(error.rawValue)"))
        }
        return nil
    }

    @MainActor
    public func isAttributeSettable(named attributeName: String) -> Bool {
        var settable: DarwinBoolean = false
        let error = AXUIElementIsAttributeSettable(underlyingElement, attributeName as CFString, &settable)
        if error != .success {
            GlobalAXLogger.shared.log(AXLogEntry(
                level: .warning,
                message: "Error checking if attribute \(attributeName) is settable: \(error.stringValue)"
            ))
            return false
        }
        return settable.boolValue
    }

    @MainActor
    public func parameterizedAttribute<T>(_ attribute: Attribute<T>, parameter: Any) -> T? {
        var value: CFTypeRef?
        let error: AXError

        // Need to bridge the parameter to CFTypeRef
        let cfParameter: CFTypeRef
        if let num = parameter as? NSNumber {
            cfParameter = num
        } else if let str = parameter as? String {
            cfParameter = str as CFString
        } else if let el = parameter as? Element {
            cfParameter = el.underlyingElement
        } else {
            // Fallback for other types or if bridging is complex; might need more specific handling
            // For now, attempt to bridge directly, or log error if not possible
            if CFGetTypeID(parameter as CFTypeRef) == 0 { // Heuristic: Check if it's already a CFTypeRef or bridgable
                GlobalAXLogger.shared.log(AXLogEntry(
                    level: .debug,
                    message: "Parameterized attribute '\(attribute.rawValue)' called with " +
                        "non-CF bridgable Swift type: \(type(of: parameter)). This might fail."
                ))
            }
            cfParameter = parameter as CFTypeRef // This can crash if parameter is not CF-bridgable
        }

        error = AXUIElementCopyParameterizedAttributeValue(self.underlyingElement, attribute.rawValue as CFString, cfParameter, &value)

        if error != .success {
            if error != .noValue {
                GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "Error \(error.rawValue) fetching parameterized attribute '\(attribute.rawValue)'."))
            }
            return nil
        }
        guard let unwrappedCFValue = value else {
            GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "Parameterized attribute '\(attribute.rawValue)' value was nil after fetch."))
            return nil
        }
        // Use the type conversion functionality from Element+TypeConversion.swift
        return convertCFTypeToSwiftType(unwrappedCFValue, attribute: attribute)
    }

    @MainActor
    public func press() -> Bool {
        do {
            _ = try performAction(AXActionNames.kAXPressAction)
            return true
        } catch {
            return false
        }
    }

    @MainActor
    public func pick() -> Bool {
        do {
            _ = try performAction(AXActionNames.kAXPickAction)
            return true
        } catch {
            return false
        }
    }

    @MainActor
    public func showMenu() -> Bool {
        do {
            _ = try performAction(AXActionNames.kAXShowMenuAction)
            return true
        } catch {
            return false
        }
    }

    @MainActor
    public func setValue(_ value: Any, forAttribute attributeName: String) -> Bool {
        // Bridge the Swift value to CFTypeRef
        // Note: This bridging is basic. For complex types or specific CF types, more handling may be needed.
        let cfValue: CFTypeRef
        if let strValue = value as? String {
            cfValue = strValue as CFString
        } else if let boolValue = value as? Bool {
            cfValue = (boolValue ? kCFBooleanTrue : kCFBooleanFalse) as CFBoolean
        } else if let numValue = value as? NSNumber { // Handles Int, Double, etc. that bridge to NSNumber
            cfValue = numValue
        } else if let elementValue = value as? Element {
            cfValue = elementValue.underlyingElement
        } else {
            // Attempt direct bridging for other types; may fail if not directly bridgable.
            // Consider logging a warning or throwing an error for unhandled types.
            let warningMsg = "Attempting to set attribute '\\(attributeName)' with potentially "
            let warningDetail = "non-CF-bridgable Swift type: \\(type(of: value)). "
            let warningEnd = "This might fail or lead to unexpected behavior."
            GlobalAXLogger.shared.log(AXLogEntry(
                level: .warning,
                message: warningMsg + warningDetail + warningEnd
            ))
            cfValue = value as CFTypeRef // This can crash if 'value' is not CF-bridgable
        }

        let error = AXUIElementSetAttributeValue(self.underlyingElement, attributeName as CFString, cfValue)
        if error == .success {
            let msg = "Successfully set attribute '\\(attributeName)' to '\\(value)' on "
            GlobalAXLogger.shared.log(AXLogEntry(
                level: .debug,
                message: msg + "\\(self.briefDescription(option: .short))"
            ))
            return true
        } else {
            GlobalAXLogger.shared.log(AXLogEntry(
                level: .error,
                message: "Failed to set attribute '\\(attributeName)' to '\\(value)' on " +
                    "\\(self.briefDescription(option: .short)): \\(error.stringValue)"
            ))
            return false
        }
    }
}

// Path structure to represent element path
public struct Path {
    public let components: [String]

    public init(components: [String]) {
        self.components = components
    }
}
