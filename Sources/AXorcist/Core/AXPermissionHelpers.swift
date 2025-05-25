//
//  AXPermissionHelpers.swift
//  AXorcist
//
//  Enhanced accessibility permissions utilities
//

import ApplicationServices
import Foundation

public struct AXPermissionHelpers {
    /// Ask for accessibility permissions if needed, showing the system prompt
    public static func askForAccessibilityIfNeeded() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary?)
    }

    /// Check if the app has accessibility permissions without prompting
    public static func hasAccessibilityPermissions() -> Bool {
        return AXIsProcessTrusted()
    }

    /// Check if the app is sandboxed
    public static func isSandboxed() -> Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

    /// Request permissions with a custom completion handler
    /// Note: This will show the system prompt if permissions are not granted
    public static func requestPermissions(completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let hasPermissions = askForAccessibilityIfNeeded()
            DispatchQueue.main.async {
                completion(hasPermissions)
            }
        }
    }

    /// Monitor permission changes with a callback
    /// Returns a closure to stop monitoring
    public static func monitorPermissionChanges(
        interval: TimeInterval = 1.0,
        onChange: @escaping (Bool) -> Void
    ) -> () -> Void {
        var lastState = hasAccessibilityPermissions()
        onChange(lastState)

        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            let currentState = hasAccessibilityPermissions()
            if currentState != lastState {
                lastState = currentState
                onChange(currentState)
            }
        }

        return { timer.invalidate() }
    }
}
