// AXTrustUtil.swift - Utility for checking and prompting for AX API trust.

import AppKit // Added for NSWorkspace
import ApplicationServices
import Foundation

@MainActor // Make the whole enum MainActor isolated
public enum AXTrustUtil {
    // MARK: Public

    /// Checks if the current process is trusted for accessibility access.
    /// - Parameter promptIfNeeded: If true, the system will prompt the user if not trusted.
    /// - Returns: True if the process is trusted, false otherwise.
    public static func checkAccessibilityPermissions(promptIfNeeded: Bool = true) -> Bool {
        // Use the captured CFStringRef.
        let options =
            [axTrustedCheckOptionPromptInternal: promptIfNeeded ? kCFBooleanTrue : kCFBooleanFalse] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Opens the accessibility settings in System Settings (System Preferences).
    @MainActor
    public static func openAccessibilitySettings() {
        // For macOS 13 and later, use the new URL scheme
        // For earlier versions, use the old preference pane path
        // This code prefers the modern approach if available.
        let settingsURLString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

        // Fallback for older macOS versions if needed, though less common now.
        // else {
        //    settingsURLString = "com.apple.preference.security?Privacy_Accessibility"
        // }

        if let url = URL(string: settingsURLString) {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Private

    // Capture the C global safely within the MainActor context.
    @MainActor private static let axTrustedCheckOptionPromptInternal: CFString = kAXTrustedCheckOptionPrompt
}
