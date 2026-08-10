// AccessibilityPermissions.swift - Utility for checking and managing accessibility permissions.

import AppKit // For NSRunningApplication
import ApplicationServices // For AXIsProcessTrusted(), AXUIElementCreateSystemWide(), etc.
import Foundation

// Removed private let kAXTrustedCheckOptionPromptKey = "AXTrustedCheckOptionPrompt"

// debug() is assumed to be globally available from Logging.swift
// getParentProcessName() is assumed to be globally available from ProcessUtils.swift
// kAXFocusedUIElementAttribute is assumed to be globally available from AccessibilityConstants.swift
// AccessibilityError is from AccessibilityError.swift

public struct AXPermissionsStatus {
    public let isAccessibilityApiEnabled: Bool
    public let isProcessTrustedForAccessibility: Bool
    public var automationStatus: [String: Bool] =
        [:] // BundleID: Bool (true if permitted, false if denied, nil if not checked or app not running)
    public var overallErrorMessages: [String] = []

    public var canUseAccessibility: Bool {
        self.isAccessibilityApiEnabled && self.isProcessTrustedForAccessibility
    }

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
public func getPermissionsStatus(
    checkAutomationFor bundleIDs: [String] = []) -> AXPermissionsStatus
{
    axDebugLog(
        "Starting full permission status check.",
        file: #file,
        function: #function,
        line: #line)

    let isProcessTrusted = AXPermissionHelpers.hasAccessibilityPermissions()
    let isSandboxed = AXPermissionHelpers.isSandboxed()

    if isSandboxed {
        axWarningLog("Process is running in sandbox, some features may be limited.")
    }

    logProcessTrustStatus(isProcessTrusted)

    var automationStatus: [String: Bool] = [:]
    var collectedErrorMessages: [String] = []

    if !bundleIDs.isEmpty, isProcessTrusted {
        let results = checkAutomationPermissions(for: bundleIDs)
        automationStatus = results.automationStatus
        collectedErrorMessages = results.errorMessages
    } else if !bundleIDs.isEmpty {
        axDebugLog(
            "Skipping automation permission checks because basic accessibility " +
                "(isProcessTrusted: \(isProcessTrusted)) is not met.",
            file: #file,
            function: #function,
            line: #line)
    }

    let finalStatus = AXPermissionsStatus(
        isAccessibilityApiEnabled: isProcessTrusted,
        isProcessTrustedForAccessibility: isProcessTrusted,
        automationStatus: automationStatus,
        overallErrorMessages: collectedErrorMessages)
    axDebugLog(
        "Finished permission status check. isAccessibilityApiEnabled: \(finalStatus.isAccessibilityApiEnabled), " +
            "isProcessTrusted: \(finalStatus.isProcessTrustedForAccessibility)",
        file: #file,
        function: #function,
        line: #line)
    return finalStatus
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

private func checkAutomationPermissions(
    for bundleIDs: [String]) -> (automationStatus: [String: Bool], errorMessages: [String])
{
    var automationStatus: [String: Bool] = [:]
    var collectedErrorMessages: [String] = []

    axDebugLog(
        "Checking automation permissions for bundle IDs: \(bundleIDs.joined(separator: ", "))",
        file: #file,
        function: #function,
        line: #line)

    for bundleID in bundleIDs {
        let result = checkSingleBundleAutomation(bundleID)
        if let status = result.status {
            automationStatus[bundleID] = status
        }
        if let error = result.errorMessage {
            collectedErrorMessages.append(error)
        }
    }

    return (automationStatus, collectedErrorMessages)
}

private func checkSingleBundleAutomation(_ bundleID: String) -> (status: Bool?, errorMessage: String?) {
    guard NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first != nil else {
        axDebugLog(
            "Application with bundle ID '\(bundleID)' is not running. Cannot check automation status.",
            file: #file,
            function: #function,
            line: #line)
        return (nil, nil)
    }

    guard var target = makeAutomationTarget(bundleID: bundleID) else {
        let message = "Could not create an Apple Event target for bundle ID '\(bundleID)'."
        axErrorLog(message, file: #file, function: #function, line: #line)
        return (nil, message)
    }
    defer { AEDisposeDesc(&target) }

    let nativeStatus = AEDeterminePermissionToAutomateTarget(
        &target,
        typeWildCard,
        typeWildCard,
        false)
    return automationPermissionResult(for: nativeStatus, bundleID: bundleID)
}

private func makeAutomationTarget(bundleID: String) -> AEDesc? {
    let bundleIDData = Data(bundleID.utf8)
    guard !bundleIDData.isEmpty else { return nil }

    var target = AEDesc()
    let status = bundleIDData.withUnsafeBytes { bytes in
        AECreateDesc(
            typeApplicationBundleID,
            bytes.baseAddress,
            bundleIDData.count,
            &target)
    }
    guard status == noErr else { return nil }
    return target
}

func automationPermissionResult(
    for nativeStatus: OSStatus,
    bundleID: String) -> (status: Bool?, errorMessage: String?)
{
    switch nativeStatus {
    case noErr:
        axDebugLog("Native automation permission check for \(bundleID) succeeded.")
        return (true, nil)
    case OSStatus(procNotFound):
        return (nil, nil)
    case OSStatus(errAEEventWouldRequireUserConsent):
        let message = "Automation permission for \(bundleID) has not been determined."
        axWarningLog(message)
        return (false, message)
    case OSStatus(errAEEventNotPermitted), OSStatus(errAETargetAddressNotPermitted):
        let message = "Automation denied for \(bundleID) (Code: \(nativeStatus))."
        axWarningLog(message)
        return (false, message)
    default:
        let message = "Automation permission check failed for \(bundleID) (Code: \(nativeStatus))."
        axWarningLog(message)
        return (false, message)
    }
}
