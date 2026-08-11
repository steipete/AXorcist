// Element+Actions.swift - Action-related methods for Element

import ApplicationServices
import Foundation

// GlobalAXLogger should be available

/// Action-related extension for Element
extension Element {
    // MARK: - Actions

    @MainActor
    public func isActionSupported(_ actionName: String) -> Bool {
        self.supportedActions()?.contains(actionName) ?? false
    }

    @MainActor
    @discardableResult
    public func performAction(_ actionName: Attribute<String>) throws -> Element {
        try self.performAction(actionName.rawValue)
    }

    @MainActor
    @discardableResult
    public func performAction(_ actionName: String) throws -> Element {
        try self.performAction(actionName, using: AXUIElementPerformAction)
    }

    @MainActor
    @discardableResult
    func performAction(
        _ actionName: String,
        using performer: (AXUIElement, CFString) -> AXError) throws -> Element
    {
        let description = GlobalAXLogger.shared.isLoggingEnabled
            ? self.briefDescription(option: .smart)
            : nil
        if let description {
            axDebugLog("Attempting to perform action '\(actionName)' on element: \(description)")
        }

        try performer(self.underlyingElement, actionName as CFString).throwIfError()

        if let description {
            axInfoLog("Successfully performed action '\(actionName)' on element: \(description)")
        }
        return self
    }

    /// Modern enum-based performAction method with cleaner syntax
    /// Example: try element.performAction(.raise)
    @MainActor
    @discardableResult
    public func performAction(_ action: AXAction) throws -> Element {
        try self.performAction(action.rawValue)
    }
}
