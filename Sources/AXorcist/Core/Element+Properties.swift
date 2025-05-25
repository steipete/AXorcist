import ApplicationServices
import Foundation
// GlobalAXLogger should be available

// MARK: - Element Common Attribute Getters & Status Properties

extension Element {
    // Common Attribute Getters - now simplified
    @MainActor public func role() -> String? {
        return attribute(Attribute<String>.role)
    }
    @MainActor public func subrole() -> String? {
        return attribute(Attribute<String>.subrole)
    }
    @MainActor public func title() -> String? {
        return attribute(Attribute<String>.title)
    }
    // Renamed from 'description' to 'descriptionText'
    @MainActor public func descriptionText() -> String? {
        return attribute(Attribute<String>.description)
    }
    @MainActor public func isEnabled() -> Bool? {
        return attribute(Attribute<Bool>.enabled)
    }
    @MainActor public func value() -> Any? { // Returns Any? as original
        return attribute(Attribute<Any>(AXAttributeNames.kAXValueAttribute))
    }
    @MainActor public func roleDescription() -> String? {
        return attribute(Attribute<String>.roleDescription)
    }
    @MainActor public func help() -> String? {
        return attribute(Attribute<String>.help)
    }
    @MainActor public func identifier() -> String? {
        return attribute(Attribute<String>.identifier)
    }

    // Status Properties - simplified
    @MainActor public func isFocused() -> Bool? {
        return attribute(Attribute<Bool>.focused)
    }
    @MainActor public func isHidden() -> Bool? {
        return attribute(Attribute<Bool>.hidden)
    }
    @MainActor public func isElementBusy() -> Bool? {
        return attribute(Attribute<Bool>.busy)
    }

    @MainActor public func isIgnored() -> Bool { // Original logic for isIgnored
        return attribute(Attribute<Bool>.hidden) == true
    }

    @MainActor public func pid() -> pid_t? {
        var processID: pid_t = 0
        let error = AXUIElementGetPid(self.underlyingElement, &processID)
        if error == .success {
            return processID
        }
        axDebugLog("Failed to get PID for element: \(error.rawValue)",
                   details: ["element": String(describing: self.underlyingElement)])
        return nil
    }

    // Hierarchy and Relationship Getters - simplified
    @MainActor public func parent() -> Element? {
        guard let parentElementUI: AXUIElement = attribute(.parent) else { return nil }
        return Element(parentElementUI)
    }

    @MainActor public func windows() -> [Element]? {
        guard let windowElementsUI: [AXUIElement] = attribute(.windows) else { return nil }
        return windowElementsUI.map { Element($0) }
    }

    @MainActor public func mainWindow() -> Element? {
        guard let windowElementUI = attribute(.mainWindow) else { return nil }
        return Element(windowElementUI)
    }

    @MainActor public func focusedWindow() -> Element? {
        guard let windowElementUI = attribute(.focusedWindow) else { return nil }
        return Element(windowElementUI)
    }

    // Attempts to get the focused UI element within this element (e.g., a focused text field in a window).
    @MainActor
    public func focusedUIElement() -> Element? {
        // Use the specific type for the attribute, non-optional generic
        guard let elementUI: AXUIElement = attribute(Attribute<AXUIElement>.focusedUIElement) else { return nil }
        return Element(elementUI)
    }

    // Action-related - simplified
    @MainActor
    public func supportedActions() -> [String]? {
        return attribute(Attribute<[String]>.actionNames)
    }

    // domIdentifier - simplified to a single method, was previously a computed property and a method.
    @MainActor public func domIdentifier() -> String? {
        return attribute(Attribute<String>(AXAttributeNames.kAXDOMIdentifierAttribute))
    }

    // @MainActor public func children() -> [Element]? { self.attribute(.children)?.map { Element($0) } }

    @MainActor public func defaultButton() -> Element? {
        guard let buttonAXUIElement = attribute(.defaultButton) else { return nil }
        return Element(buttonAXUIElement)
    }

    @MainActor public func cancelButton() -> Element? {
        guard let buttonAXUIElement = attribute(.cancelButton) else { return nil }
        return Element(buttonAXUIElement)
    }

    // Specific UI Buttons in a Window
    @MainActor public func closeButton() -> Element? {
        guard let buttonAXUIElement = attribute(.closeButton) else { return nil }
        return Element(buttonAXUIElement)
    }

    @MainActor public func zoomButton() -> Element? {
        guard let buttonAXUIElement = attribute(.zoomButton) else { return nil }
        return Element(buttonAXUIElement)
    }

    @MainActor public func minimizeButton() -> Element? {
        guard let buttonAXUIElement = attribute(.minimizeButton) else { return nil }
        return Element(buttonAXUIElement)
    }

    @MainActor public func toolbarButton() -> Element? {
        guard let buttonAXUIElement = attribute(.toolbarButton) else { return nil }
        return Element(buttonAXUIElement)
    }

    @MainActor public func fullScreenButton() -> Element? {
        guard let buttonAXUIElement = attribute(.fullScreenButton) else { return nil }
        return Element(buttonAXUIElement)
    }

    // Proxy (e.g. for web content)
    @MainActor public func proxy() -> Element? {
        guard let proxyAXUIElement = attribute(.proxy) else { return nil }
        return Element(proxyAXUIElement)
    }

    // Grow Area (e.g. for resizing window)
    @MainActor public func growArea() -> Element? {
        guard let growAreaAXUIElement = attribute(.growArea) else { return nil }
        return Element(growAreaAXUIElement)
    }

    // Table/List/Outline properties
    // @MainActor public func rows() -> [Element]? { self.attribute(.rows)?.map { Element($0) } }

    @MainActor public func header() -> Element? {
        guard let headerAXUIElement = attribute(.header) else { return nil }
        return Element(headerAXUIElement)
    }

    // Scroll Area properties
    @MainActor public func horizontalScrollBar() -> Element? {
        guard let scrollBarAXUIElement = attribute(.horizontalScrollBar) else { return nil }
        return Element(scrollBarAXUIElement)
    }

    @MainActor public func verticalScrollBar() -> Element? {
        guard let scrollBarAXUIElement = attribute(.verticalScrollBar) else { return nil }
        return Element(scrollBarAXUIElement)
    }

    // Common Value-Holding Attributes (as specific types)
    // ... existing code ...

    // MARK: - Attribute Names
    @MainActor public func attributeNames() -> [String]? {
        var attrNames: CFArray?
        let error = AXUIElementCopyAttributeNames(self.underlyingElement, &attrNames)
        if error == .success, let names = attrNames as? [String] {
            return names
        }
        axDebugLog("Failed to get attribute names for element: \(error.rawValue)")
        return nil
    }
}
