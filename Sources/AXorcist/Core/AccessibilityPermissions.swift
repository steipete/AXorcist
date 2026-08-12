// AccessibilityPermissions.swift - Utility for checking and managing accessibility permissions.

import ApplicationServices // For AXIsProcessTrusted(), AXUIElementCreateSystemWide(), etc.

// Removed private let kAXTrustedCheckOptionPromptKey = "AXTrustedCheckOptionPrompt"

// debug() is assumed to be globally available from Logging.swift
// getParentProcessName() is assumed to be globally available from ProcessUtils.swift
// kAXFocusedUIElementAttribute is assumed to be globally available from AccessibilityConstants.swift
// AccessibilityError is from AccessibilityError.swift

public struct AXPermissionsStatus {
    public let isAccessibilityApiEnabled: Bool
    public let isProcessTrustedForAccessibility: Bool

    @available(
        *,
        deprecated,
        message: "AXorcist no longer probes Apple Events automation permission; this status remains empty.")
    public var automationStatus: [String: Bool] = [:]
    public var overallErrorMessages: [String] = []

    public var canUseAccessibility: Bool {
        self.isAccessibilityApiEnabled && self.isProcessTrustedForAccessibility
    }

    @available(
        *,
        deprecated,
        message: "AXorcist no longer probes Apple Events automation permission; this result is unknown.")
    public func canAutomate(bundleID: String) -> Bool? {
        self.automationStatus[bundleID]
    }
}

@MainActor
public func checkAccessibilityPermissions(promptIfNeeded: Bool = true) throws {
    let hasPermissions = promptIfNeeded ?
        AXPermissionHelpers.askForAccessibilityIfNeeded() :
        AXPermissionHelpers.hasAccessibilityPermissions()

    if !hasPermissions {
        let parentName = getParentProcessName()
        let errorDetail = parentName != nil ? "Hint: Grant accessibility permissions to \(parentName!)." :
            "Hint: Ensure the application running this tool has Accessibility permissions."
        axErrorLog(
            "Accessibility check failed. Details: \(errorDetail)",
            file: #file,
            function: #function,
            line: #line)
        throw AccessibilityError.notAuthorized(errorDetail)
    } else {
        axDebugLog(
            "Accessibility permissions are granted.",
            file: #file,
            function: #function,
            line: #line)
    }
}

@MainActor
public func getPermissionsStatus() -> AXPermissionsStatus {
    axDebugLog(
        "Starting Accessibility permission status check.",
        file: #file,
        function: #function,
        line: #line)

    let isProcessTrusted = AXPermissionHelpers.hasAccessibilityPermissions()
    let isSandboxed = AXPermissionHelpers.isSandboxed()

    if isSandboxed {
        axWarningLog("Process is running in sandbox, some features may be limited.")
    }

    logProcessTrustStatus(isProcessTrusted)

    let finalStatus = AXPermissionsStatus(
        isAccessibilityApiEnabled: isProcessTrusted,
        isProcessTrustedForAccessibility: isProcessTrusted,
        automationStatus: [:],
        overallErrorMessages: [])
    axDebugLog(
        "Finished permission status check. isAccessibilityApiEnabled: \(finalStatus.isAccessibilityApiEnabled), " +
            "isProcessTrusted: \(finalStatus.isProcessTrustedForAccessibility)",
        file: #file,
        function: #function,
        line: #line)
    return finalStatus
}

/// Returns Accessibility permission status without probing Apple Events automation permission.
///
/// The bundle identifiers are ignored and ``AXPermissionsStatus/automationStatus`` remains empty.
/// This overload is retained only so existing source continues to compile while callers migrate to
/// ``getPermissionsStatus()``.
@available(
    *,
    deprecated,
    message: "Apple Events automation permission probing was removed; call getPermissionsStatus() instead.")
@MainActor
public func getPermissionsStatus(checkAutomationFor _: [String]) -> AXPermissionsStatus {
    getPermissionsStatus()
}

private func logProcessTrustStatus(_ isProcessTrusted: Bool) {
    axDebugLog(
        "AXIsProcessTrusted() returned: \(isProcessTrusted)",
        file: #file,
        function: #function,
        line: #line)
    if !isProcessTrusted {
        let parentName = getParentProcessName()
        let hint = parentName != nil ? "Hint: Grant accessibility permissions to \(parentName!)." :
            "Hint: Ensure the application running this tool has Accessibility permissions."
        axWarningLog(
            "Process is not trusted for Accessibility. \(hint)",
            file: #file,
            function: #function,
            line: #line)
    }
}
