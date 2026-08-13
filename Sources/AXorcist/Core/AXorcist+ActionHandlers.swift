import AppKit // For NSRunningApplication & NSValue
import ApplicationServices
import Foundation

/// Extension providing action execution handlers for AXorcist.
///
/// This extension handles:
/// - Performing accessibility actions on UI elements
/// - Action error handling
/// - Setting element values (text, numeric, selection)
/// - Complex action coordination and validation
/// - Integration with element discovery and targeting
@MainActor
extension AXorcist {
    // MARK: - Perform Action Handler

    public func handlePerformAction(command: PerformActionCommand) -> AXResponse {
        self.handlePerformAction(command: command, traversalOptions: .snapshotDefaults())
    }

    public func handlePerformAction(
        command: PerformActionCommand,
        traversalOptions: AXTraversalOptions) -> AXResponse
    {
        self.logPerformActionStart(command)

        let element: Element
        switch resolveTargetElement(
            appIdentifier: command.appIdentifier,
            pid: command.pid,
            locator: command.locator,
            maxDepthForSearch: command.maxDepthForSearch,
            traversalOptions: traversalOptions)
        {
        case let .success(resolvedElement):
            element = resolvedElement
        case let .failure(error):
            GlobalAXLogger.shared.log(AXLogEntry(level: .error, message: error.message))
            return error.response
        }

        return self.executeResolvedAction(command: command, on: element)
    }

    // MARK: - Set Focused Value Handler

    public func handleSetFocusedValue(command: SetFocusedValueCommand) -> AXResponse {
        self.handleSetFocusedValue(command: command, traversalOptions: .snapshotDefaults())
    }

    public func handleSetFocusedValue(
        command: SetFocusedValueCommand,
        traversalOptions: AXTraversalOptions) -> AXResponse
    {
        self.logSetFocusedValueStart(command)

        let element: Element
        switch resolveTargetElement(
            appIdentifier: command.appIdentifier,
            pid: command.pid,
            locator: command.locator,
            maxDepthForSearch: command.maxDepthForSearch,
            traversalOptions: traversalOptions)
        {
        case let .success(resolvedElement):
            element = resolvedElement
        case let .failure(error):
            GlobalAXLogger.shared.log(AXLogEntry(level: .error, message: error.message))
            return error.response
        }

        if self.ensureFocusCapability(for: element) {
            self.setFocus(on: element)
        }
        return self.executeSetValue(value: command.value, on: element)
    }

    // MARK: - Extract Text Handler

    public func handleExtractText(command: ExtractTextCommand) -> AXResponse {
        self.handleExtractText(command: command, traversalOptions: .snapshotDefaults())
    }

    public func handleExtractText(
        command: ExtractTextCommand,
        traversalOptions: AXTraversalOptions) -> AXResponse
    {
        GlobalAXLogger.shared.log(AXLogEntry(
            level: .info,
            message: "HandleExtractText: App '\(String(describing: command.appIdentifier))', " +
                "Locator: \(command.locator), " +
                "IncludeChildren: \(String(describing: command.includeChildren)), " +
                "MaxDepth: \(String(describing: command.maxDepth))"))

        let element: Element
        switch resolveTargetElement(
            appIdentifier: command.appIdentifier,
            pid: command.pid,
            locator: command.locator,
            maxDepthForSearch: command.maxDepthForSearch,
            traversalOptions: traversalOptions)
        {
        case let .success(resolvedElement):
            element = resolvedElement
        case let .failure(error):
            GlobalAXLogger.shared.log(AXLogEntry(level: .error, message: error.message))
            return error.response
        }
        GlobalAXLogger.shared.log(AXLogEntry(
            level: .debug,
            message: "HandleExtractText: Found element: " +
                "\(element.briefDescription(option: ValueFormatOption.smart))"))

        if let textContent = getElementTextualContent(
            element: element,
            includeChildren: command.includeChildren ?? true,
            maxDepth: command.maxDepth ?? 5)
        {
            GlobalAXLogger.shared.log(AXLogEntry(
                level: .info,
                message: "HandleExtractText: Extracted text: '\(textContent)'"))
            return .successResponse(payload: AnyCodable(TextPayload(text: textContent)))
        } else {
            let message = "HandleExtractText: No text content found for " +
                "element \(element.briefDescription(option: ValueFormatOption.smart))."
            GlobalAXLogger.shared.log(AXLogEntry(level: .info, message: message))
            return .successResponse(payload: AnyCodable(TextPayload(text: ""))) // Success, but no text
        }
    }
}

// MARK: - Shared Helpers

extension AXorcist {
    private func logPerformActionStart(_ command: PerformActionCommand) {
        GlobalAXLogger.shared.log(AXLogEntry(
            level: .info,
            message: "HandlePerformAction: App '\(String(describing: command.appIdentifier))', " +
                "Locator: \(command.locator), Action: \(command.action), " +
                "Value: \(String(describing: command.value))"))
    }

    private func logSetFocusedValueStart(_ command: SetFocusedValueCommand) {
        GlobalAXLogger.shared.log(AXLogEntry(
            level: .info,
            message: "HandleSetFocusedValue: App '\(String(describing: command.appIdentifier))', " +
                "Locator: \(command.locator), Value: '\(command.value)'"))
    }

    func executeResolvedAction(
        command: PerformActionCommand,
        on element: Element,
        performer: (Element, String) throws -> Void = { element, action in
            try element.performAction(action)
        },
        valueSetter: (Element, String) throws -> Void = { element, value in
            try element.setValue(value)
        },
        supportedActions: (Element) -> [String]? = { element in
            element.supportedActions()
        }) -> AXResponse
    {
        guard command.action == AXActionNames.kAXSetValueAction else {
            return self.executeAction(
                action: command.action,
                on: element,
                value: command.value,
                performer: performer,
                supportedActions: supportedActions)
        }

        guard let value = command.value?.value as? String else {
            let message = "HandlePerformAction: AXSetValue requires a string action_value. No value was dispatched."
            GlobalAXLogger.shared.log(AXLogEntry(level: .error, message: message))
            return .errorResponse(message: message, code: .invalidParameter)
        }

        return self.executeSetValue(value: value, on: element, setter: valueSetter)
    }

    func executeAction(
        action: String,
        on element: Element,
        value: AnyCodable?,
        performer: (Element, String) throws -> Void = { element, action in
            try element.performAction(action)
        },
        supportedActions: (Element) -> [String]? = { element in
            element.supportedActions()
        }) -> AXResponse
    {
        if let actionValue = value?.value {
            GlobalAXLogger.shared.log(AXLogEntry(
                level: .warning,
                message: "HandlePerformAction: Action value provided but not used: \(actionValue)"))
        }

        do {
            try performer(element, action)
            GlobalAXLogger.shared.log(AXLogEntry(
                level: .info,
                message: "HandlePerformAction: Successfully performed action '\(action)'."))
            return .successResponse(
                payload: AnyCodable(["message": "Action '\(action)' performed successfully."]))
        } catch let error as AccessibilitySystemError {
            // The platform can return cannotComplete after dispatch, so classify once and never retry here.
            return self.actionFailureResponse(
                action: action,
                element: element,
                error: error,
                supportedActions: supportedActions)
        } catch {
            let errorMessage = "HandlePerformAction: Failed to perform action '\(action)'. Error: \(error)"
            GlobalAXLogger.shared.log(AXLogEntry(level: .error, message: errorMessage))
            return .errorResponse(message: errorMessage, code: .actionFailed)
        }
    }

    func executeSetValue(
        value: String,
        on element: Element,
        setter: (Element, String) throws -> Void = { element, value in
            try element.setValue(value)
        }) -> AXResponse
    {
        do {
            try setter(element, value)
            GlobalAXLogger.shared.log(AXLogEntry(
                level: .info,
                message: "Successfully set the element's AXValue attribute."))
            return .successResponse(payload: AnyCodable(["message": "Value set successfully."]))
        } catch let error as AccessibilitySystemError {
            let message = "Failed to set AXValue. Error: \(error.localizedDescription) " +
                "(AXError \(error.axError.rawValue))."
            GlobalAXLogger.shared.log(AXLogEntry(level: .error, message: message))
            return .errorResponse(message: message, code: error.axError.valueResponseCode)
        } catch {
            let message = "Failed to set AXValue. Error: \(error.localizedDescription)"
            GlobalAXLogger.shared.log(AXLogEntry(level: .error, message: message))
            return .errorResponse(message: message, code: .actionFailed)
        }
    }

    private func actionFailureResponse(
        action: String,
        element: Element,
        error: AccessibilitySystemError,
        supportedActions: (Element) -> [String]?) -> AXResponse
    {
        let summary = error.axError == .actionUnsupported
            ? "Action '\(action)' is not supported."
            : "Failed to perform action '\(action)'."
        var errorMessage = "HandlePerformAction: \(summary) " +
            "Error: \(error.localizedDescription) (AXError \(error.axError.rawValue))."
        if error.axError == .actionUnsupported {
            let availableActions = supportedActions(element) ?? []
            errorMessage += " Available actions: [\(availableActions.joined(separator: ", "))]"
        }
        GlobalAXLogger.shared.log(AXLogEntry(level: .error, message: errorMessage))
        return .errorResponse(message: errorMessage, code: error.axError.actionResponseCode)
    }

    private func ensureFocusCapability(for element: Element) -> Bool {
        if element.isAttributeSettable(named: AXAttributeNames.kAXFocusedAttribute) {
            return true
        }

        let elementDescription = GlobalAXLogger.shared.isLoggingEnabled
            ? element.briefDescription(option: .smart)
            : nil
        GlobalAXLogger.shared.log(AXLogEntry(
            level: .debug,
            message: "HandleSetFocusedValue: Element not directly focusable by kAXFocusedAttribute, " +
                "attempting kAXPressAction."))
        do {
            try element.performAction(.press)
            GlobalAXLogger.shared.log(AXLogEntry(
                level: .debug,
                message: "HandleSetFocusedValue: Successfully pressed element to potentially gain focus."))
        } catch let error as AccessibilitySystemError where error.axError == .actionUnsupported {
            let focusError = [
                "HandleSetFocusedValue: Element \(elementDescription ?? "target") is not focusable",
                "(kAXFocusedAttribute not settable and kAXPressAction not supported).",
            ].joined(separator: " ")
            GlobalAXLogger.shared.log(AXLogEntry(level: .warning, message: focusError))
        } catch let error as AccessibilitySystemError {
            let pressError = [
                "HandleSetFocusedValue: Element \(elementDescription ?? "target") could not be pressed",
                "to potentially gain focus. Error: \(error.localizedDescription)",
                "(AXError \(error.axError.rawValue)).",
            ].joined(separator: " ")
            GlobalAXLogger.shared.log(AXLogEntry(level: .warning, message: pressError))
        } catch {
            let pressError = [
                "HandleSetFocusedValue: Element \(elementDescription ?? "target") could not be pressed",
                "to potentially gain focus. Error: \(error)",
            ].joined(separator: " ")
            GlobalAXLogger.shared.log(AXLogEntry(level: .warning, message: pressError))
        }
        return false
    }

    private func setFocus(on element: Element) {
        let elementDescription = element.briefDescription(option: ValueFormatOption.smart)
        GlobalAXLogger.shared.log(AXLogEntry(
            level: .debug,
            message: "HandleSetFocusedValue: Attempting to set kAXFocusedAttribute to true for \(elementDescription)"))
        if element.setValue(true, forAttribute: AXAttributeNames.kAXFocusedAttribute) {
            return
        }
        GlobalAXLogger.shared.log(AXLogEntry(
            level: .warning,
            message: [
                "HandleSetFocusedValue: Failed to set kAXFocusedAttribute for \(elementDescription),",
                "but proceeding to set value.",
            ].joined(separator: " ")))
    }
}
