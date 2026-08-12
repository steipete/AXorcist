// Element.swift - Wrapper for AXUIElement for a more Swift-idiomatic interface

import AppKit // Added to provide NSRunningApplication and NSWorkspace
@preconcurrency import ApplicationServices // For AXUIElement and other C APIs
import Foundation

/// A Swift-idiomatic wrapper around macOS AXUIElement for accessibility automation.
///
/// Element provides a modern Swift interface for interacting with UI elements through
/// the macOS accessibility APIs. It can represent any UI element from applications,
/// windows, buttons, text fields, and more.
///
/// ## Topics
///
/// ### Creating Elements
/// - ``init(_:)``
/// - ``init(_:attributes:children:actions:)``
///
/// ### Element Properties
/// - ``underlyingElement``
/// - ``attributes``
/// - ``prefetchedChildren``
/// - ``actions``
///
/// ### Element Operations
/// - ``attribute(_:)``
/// - ``setValue(_:forAttribute:)``
/// - ``performAction(_:)``
///
/// ## Usage
///
/// ```swift
/// // Wrap an AXUIElement
/// let element = Element(axElement)
///
/// // Get element properties
/// let role = element.role()
/// let title = element.title()
///
/// // Perform actions
/// try element.performAction(.press)
/// ```
public struct Element: Equatable, Hashable, Sendable {
    // MARK: Lifecycle

    /// Creates an Element wrapper around an AXUIElement.
    ///
    /// This initializer creates a basic wrapper that will fetch attributes,
    /// children, and actions on demand.
    ///
    /// - Parameter element: The AXUIElement to wrap
    public init(_ element: AXUIElement) {
        self.underlyingElement = element
        self.attributes = nil // Not fetched by default with this initializer
        self.prefetchedChildren = nil // Not fetched by default. Renamed from 'children'.
        self.actions = nil // Not fetched by default
    }

    /// Creates a fully populated Element with pre-fetched data.
    ///
    /// This initializer is typically used by AXorcist when creating elements
    /// from tree fetches or deep queries where all data is retrieved at once.
    ///
    /// - Parameters:
    ///   - element: The AXUIElement to wrap
    ///   - attributes: Pre-fetched accessibility attributes
    ///   - children: Pre-fetched child elements
    ///   - actions: Pre-fetched available actions
    public init(
        _ element: AXUIElement,
        attributes: [String: AttributeValue]?,
        children: [Element]?,
        actions: [String]?)
    {
        self.underlyingElement = element
        self.attributes = attributes
        self.prefetchedChildren = children // Renamed from 'children'.
        self.actions = actions
    }

    // MARK: Public

    /// The underlying AXUIElement that this Element wraps.
    ///
    /// This provides direct access to the Core Foundation accessibility element
    /// for operations that require the raw AXUIElement.
    public let underlyingElement: AXUIElement

    /// Pre-fetched accessibility attributes for this element.
    ///
    /// When populated (typically by deep queries), this contains all the
    /// accessibility attributes for the element, avoiding repeated API calls.
    public var attributes: [String: AttributeValue]?

    /// Pre-fetched child elements.
    ///
    /// When populated by deep queries, this contains all direct child elements,
    /// allowing for efficient tree traversal without additional API calls.
    public var prefetchedChildren: [Element]?

    /// Pre-fetched available actions for this element.
    ///
    /// When populated, this contains all actions that can be performed on
    /// this element (e.g., "AXPress", "AXShowMenu").
    public var actions: [String]?

    /// Implement Equatable
    public static func == (lhs: Element, rhs: Element) -> Bool {
        CFEqual(lhs.underlyingElement, rhs.underlyingElement)
    }

    /// Implement Hashable
    public func hash(into hasher: inout Hasher) {
        hasher.combine(CFHash(self.underlyingElement))
    }

    /// Generic method to get an attribute's value (converted to Swift type T)
    @MainActor
    public func attribute<T>(_ attribute: Attribute<T>) -> T? {
        // Try to get from pre-fetched attributes first
        if let storedValue = getStoredAttribute(attribute) {
            return storedValue
        }

        GlobalAXLogger.shared.log(AXLogEntry(
            level: .debug,
            message: "'\\(attribute.rawValue)' not in stored. Fetching..."))

        if T.self == [AXUIElement].self {
            return self.fetchAXUIElementArray(attribute)
        } else {
            return self.fetchAndConvertAttribute(attribute)
        }
    }

    @MainActor
    public func rawAttributeValue(named attributeName: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(self.underlyingElement, attributeName as CFString, &value)
        if error == .success {
            return value
        } else if error == .attributeUnsupported {
            GlobalAXLogger.shared.log(AXLogEntry(
                level: .debug,
                message: "Attribute \\(attributeName) unsupported for element."))
        } else if error == .noValue {
            GlobalAXLogger.shared.log(AXLogEntry(
                level: .debug,
                message: "Attribute \\(attributeName) has no value for element."))
        } else {
            GlobalAXLogger.shared.log(AXLogEntry(
                level: .debug,
                message: "Error getting attribute \\(attributeName) for element: \\(error.rawValue)"))
        }
        return nil
    }

    @MainActor
    public func isAttributeSettable(named attributeName: String) -> Bool {
        var settable: DarwinBoolean = false
        let error = AXUIElementIsAttributeSettable(underlyingElement, attributeName as CFString, &settable)
        if error != .success {
            axWarningLog("Error checking if attribute \(attributeName) is settable: \(error.stringValue)")
            return false
        }
        return settable.boolValue
    }

    @MainActor
    public func parameterizedAttribute<T>(_ attribute: Attribute<T>, parameter: Any) -> T? {
        self.parameterizedAttribute(attribute, forParameter: parameter)
    }

    @MainActor
    public func press() -> Bool {
        do {
            _ = try performAction(.press)
            return true
        } catch {
            return false
        }
    }

    @MainActor
    public func pick() -> Bool {
        do {
            _ = try performAction(.pick)
            return true
        } catch {
            return false
        }
    }

    @MainActor
    public func showMenu() -> Bool {
        do {
            _ = try performAction(.showMenu)
            return true
        } catch {
            return false
        }
    }

    // MARK: Private

    @MainActor
    private func getStoredAttribute<T>(_ attribute: Attribute<T>) -> T? {
        guard let storedAttributes = self.attributes,
              let attributeValue = storedAttributes[attribute.rawValue]
        else {
            return nil
        }

        GlobalAXLogger.shared.log(AXLogEntry(
            level: .debug,
            message: "Found '\\(attribute.rawValue)' in stored attributes."))

        // Attempt to convert AttributeValue to T
        if T.self == String.self, let strValue = attributeValue.stringValue {
            return strValue as? T
        }
        if T.self == Bool.self, let boolValue = attributeValue.boolValue {
            return boolValue as? T
        }
        if T.self == Int.self, let intValue = attributeValue.intValue {
            return intValue as? T
        }
        if T.self == [Element].self,
           let elementArray = attributeValue.anyValue as? [Element]
        {
            return elementArray as? T
        }
        if T.self == AXUIElement.self,
           let cfValue = attributeValue.anyValue as CFTypeRef?,
           CFGetTypeID(cfValue) == AXUIElementGetTypeID()
        {
            return cfValue as? T
        }

        if let val = attributeValue.anyValue as? T {
            return val
        } else {
            GlobalAXLogger.shared.log(AXLogEntry(
                level: .debug,
                message: "Stored attribute '\\(attribute.rawValue)' " +
                    "(type \\(type(of: attributeValue))) " +
                    "could not be cast to \\(String(describing: T.self))"))
            return nil
        }
    }

    @MainActor
    private func fetchAXUIElementArray<T>(_ attribute: Attribute<T>) -> T? {
        GlobalAXLogger.shared.log(AXLogEntry(
            level: .debug,
            message: "Special handling for T == [AXUIElement]. Attribute: \\(attribute.rawValue)"))
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(self.underlyingElement, attribute.rawValue as CFString, &value)

        guard error == .success else {
            if error == .noValue {
                GlobalAXLogger.shared.log(AXLogEntry(
                    level: .debug,
                    message: "Attribute '\\(attribute.rawValue)' has no value."))
            } else {
                GlobalAXLogger.shared.log(AXLogEntry(
                    level: .debug,
                    message: "Error fetching '\\(attribute.rawValue)': \\(error.rawValue)"))
            }
            return nil
        }

        if let cfArray = value, CFGetTypeID(cfArray) == CFArrayGetTypeID() {
            if let axElements = cfArray as? [AXUIElement] {
                let message = "Successfully fetched and cast \(axElements.count) AXUIElements " +
                    "for '\(attribute.rawValue)'."
                GlobalAXLogger.shared.log(AXLogEntry(
                    level: .debug,
                    message: message))
                return axElements as? T
            } else {
                let message = "CFArray for '\(attribute.rawValue)' failed to cast to [AXUIElement]."
                GlobalAXLogger.shared.log(AXLogEntry(
                    level: .debug,
                    message: message))
            }
        } else if let unwrappedValue = value {
            let typeDescription = String(describing: CFGetTypeID(unwrappedValue))
            let message = "Value for '\(attribute.rawValue)' was not a CFArray. TypeID: \(typeDescription)"
            GlobalAXLogger.shared.log(AXLogEntry(
                level: .debug,
                message: message))
        } else {
            GlobalAXLogger.shared.log(AXLogEntry(
                level: .debug,
                message: "Value for '\(attribute.rawValue)' was nil despite .success."))
        }
        return nil
    }

    @MainActor
    private func fetchAndConvertAttribute<T>(_ attribute: Attribute<T>) -> T? {
        GlobalAXLogger.shared.log(AXLogEntry(
            level: .debug,
            message: "Using basic CFTypeRef conversion for T = \\(String(describing: T.self)), " +
                "Attribute: \\(attribute.rawValue)."))
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(self.underlyingElement, attribute.rawValue as CFString, &value)

        if error != .success {
            if error != .noValue {
                GlobalAXLogger.shared.log(AXLogEntry(
                    level: .debug,
                    message: "Error \\(error.rawValue) fetching '\\(attribute.rawValue)' for basic conversion."))
            }
            return nil
        }

        guard let unwrappedCFValue = value else {
            GlobalAXLogger.shared.log(AXLogEntry(
                level: .debug,
                message: "Value was nil for '\\(attribute.rawValue)' after fetch for basic conversion."))
            return nil
        }

        // Use the type conversion functionality from Element+TypeConversion.swift
        return convertCFTypeToSwiftType(unwrappedCFValue, attribute: attribute)
    }
}

/// Path structure to represent element path
public struct Path {
    // MARK: Lifecycle

    public init(components: [String]) {
        self.components = components
    }

    // MARK: Public

    public let components: [String]
}
