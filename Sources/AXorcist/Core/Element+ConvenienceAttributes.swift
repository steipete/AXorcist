//
//  Element+ConvenienceAttributes.swift
//  AXorcist
//
//  Convenience attribute accessors for common operations
//

import ApplicationServices
import CoreGraphics
import Foundation

extension Element {
    // MARK: - Position and Size

    /// Get the position (CGPoint) of the element
    @MainActor
    public func position() -> CGPoint? {
        return attribute(Attribute<CGPoint>.position)
    }

    /// Set the position of the element
    @MainActor
    public func setPosition(_ point: CGPoint) -> AXError {
        guard let axValue = AXValue.create(point: point) else {
            return .failure
        }
        return AXUIElementSetAttributeValue(underlyingElement, AXAttributeNames.kAXPositionAttribute as CFString, axValue)
    }

    /// Get the size (CGSize) of the element
    @MainActor
    public func size() -> CGSize? {
        return attribute(Attribute<CGSize>.size)
    }

    /// Set the size of the element
    @MainActor
    public func setSize(_ size: CGSize) -> AXError {
        guard let axValue = AXValue.create(size: size) else {
            return .failure
        }
        return AXUIElementSetAttributeValue(underlyingElement, AXAttributeNames.kAXSizeAttribute as CFString, axValue)
    }

    /// Get the frame (CGRect) of the element
    @MainActor
    public func frame() -> CGRect? {
        guard let origin = position(),
              let size = size() else {
            return nil
        }
        return CGRect(origin: origin, size: size)
    }

    /// Set the frame of the element
    @MainActor
    public func setFrame(_ rect: CGRect) {
        _ = setPosition(rect.origin)
        _ = setSize(rect.size)
    }

    /// Set the frame using separate origin and size
    @MainActor
    public func setFrame(origin: CGPoint, size: CGSize) {
        _ = setPosition(origin)
        _ = setSize(size)
    }

    // MARK: - Window State

    /// Check if the element is minimized
    @MainActor
    public func isMinimized() -> Bool? {
        return attribute(Attribute<Bool>.minimized)
    }

    /// Set the minimized state
    @MainActor
    public func setMinimized(_ isMinimized: Bool) -> AXError {
        return AXUIElementSetAttributeValue(underlyingElement, AXAttributeNames.kAXMinimizedAttribute as CFString, isMinimized as CFBoolean)
    }

    /// Check if the element is in fullscreen
    @MainActor
    public func isFullScreen() -> Bool? {
        return attribute(Attribute<Bool>.fullScreen)
    }

    /// Set fullscreen state
    @MainActor
    public func setFullScreen(_ fullScreen: Bool) -> AXError {
        return AXUIElementSetAttributeValue(underlyingElement, AXAttributeNames.kAXFullScreenAttribute as CFString, fullScreen as CFBoolean)
    }

    // MARK: - Text Attributes

    /// Get selected text
    @MainActor
    public func selectedText() -> String? {
        return attribute(Attribute<String>.selectedText)
    }

    /// Get selected text range
    @MainActor
    public func selectedTextRange() -> CFRange? {
        return attribute(Attribute<CFRange>.selectedTextRange)
    }

    /// Get visible character range
    @MainActor
    public func visibleCharacterRange() -> CFRange? {
        return attribute(Attribute<CFRange>.visibleCharacterRange)
    }

    /// Get number of characters
    @MainActor
    public func numberOfCharacters() -> Int? {
        return attribute(Attribute<Int>.numberOfCharacters)
    }

    // MARK: - Hierarchy Navigation

    // Note: children() method is already defined in Element+Hierarchy.swift

    /// Get selected children
    @MainActor
    public func selectedChildren() -> [Element]? {
        guard let selectedUI: [AXUIElement] = attribute(.selectedChildren) else { return nil }
        return selectedUI.map { Element($0) }
    }

    /// Get visible children
    @MainActor
    public func visibleChildren() -> [Element]? {
        guard let visibleUI: [AXUIElement] = attribute(.visibleChildren) else { return nil }
        return visibleUI.map { Element($0) }
    }

    // MARK: - Application Attributes

    /// Get the main menu bar element of an application. This is typically called on an Element representing an application.
    @MainActor
    public func mainMenu() -> Element? {
        guard let menuBarUI = attribute(Attribute<AXUIElement>.mainMenu) else { return nil }
        return Element(menuBarUI)
    }

    /// Check if the application element is the frontmost application. This is typically called on an Element representing an application.
    @MainActor
    public func isFrontmost() -> Bool? {
        return attribute(Attribute<Bool>.frontmost)
    }

    /// Check if the application represented by this element is hidden. This is typically called on an Element representing an application.
    @MainActor
    public func isApplicationHidden() -> Bool? {
        return attribute(Attribute<Bool>.hidden)
    }

    /// Check if element is main (e.g., the main window of an application). This is typically called on an Element representing a window.
    @MainActor
    public func isMain() -> Bool? {
        return attribute(Attribute<Bool>(AXAttributeNames.kAXMainAttribute))
    }

    /// Check if element is modal
    @MainActor
    public func isModal() -> Bool? {
        return attribute(Attribute<Bool>.modal)
    }

    // MARK: - Table/List Attributes

    /// Get rows
    @MainActor
    public func rows() -> [Element]? {
        guard let rowsUI: [AXUIElement] = attribute(.rows) else { return nil }
        return rowsUI.map { Element($0) }
    }

    /// Get columns
    @MainActor
    public func columns() -> [Element]? {
        guard let columnsUI: [AXUIElement] = attribute(.columns) else { return nil }
        return columnsUI.map { Element($0) }
    }

    /// Get visible rows
    @MainActor
    public func visibleRows() -> [Element]? {
        guard let rowsUI: [AXUIElement] = attribute(.visibleRows) else { return nil }
        return rowsUI.map { Element($0) }
    }

    /// Get visible columns  
    @MainActor
    public func visibleColumns() -> [Element]? {
        guard let columnsUI: [AXUIElement] = attribute(.visibleColumns) else { return nil }
        return columnsUI.map { Element($0) }
    }

    // MARK: - Value Attributes

    /// Get minimum value
    @MainActor
    public func minValue() -> Any? {
        return attribute(Attribute<Any>(AXAttributeNames.kAXMinValueAttribute))
    }

    /// Get maximum value
    @MainActor
    public func maxValue() -> Any? {
        return attribute(Attribute<Any>(AXAttributeNames.kAXMaxValueAttribute))
    }

    /// Get value increment
    @MainActor
    public func valueIncrement() -> Any? {
        return attribute(Attribute<Any>(AXAttributeNames.kAXValueIncrementAttribute))
    }

    // MARK: - URL Attribute

    /// Get URL for elements that represent disk or network items
    @MainActor
    public func url() -> URL? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(underlyingElement, AXAttributeNames.kAXURLAttribute as CFString, &value)
        guard error == .success,
              let cfURL = value as! CFURL? else {
            return nil
        }
        return cfURL as URL
    }

    // MARK: - System-Wide Element Attributes

    /// If this element is the SystemWide element, gets the currently focused application.
    /// Returns nil if this element is not the SystemWide element or if the attribute cannot be retrieved.
    @MainActor
    public func focusedApplicationElement() -> Element? {
        guard let appElementUI: AXUIElement = attribute(Attribute<AXUIElement>.focusedApplication) else { return nil }
        return Element(appElementUI)
    }
}
