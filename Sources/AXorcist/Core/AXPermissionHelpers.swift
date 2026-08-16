//
//  AXPermissionHelpers.swift
//  AXorcist
//
//  Enhanced accessibility permissions utilities
//

import ApplicationServices
import Foundation

/// Utilities for managing macOS accessibility permissions.
///
/// This structure provides convenient methods for checking and requesting accessibility
/// permissions required for AXorcist to function properly. It also includes modern
/// async/await APIs for permission monitoring.
///
/// ## Topics
///
/// ### Permission Checking
/// - ``hasAccessibilityPermissions()``
/// - ``askForAccessibilityIfNeeded()``
/// - ``isSandboxed()``
///
/// ### Async Permission Management
/// - ``requestPermissions()``
/// - ``permissionChanges(interval:)``
public enum AXPermissionHelpers {
    /// Requests accessibility permissions if needed, showing the system prompt.
    ///
    /// This method will display the macOS system dialog asking the user to grant
    /// accessibility permissions if they haven't been granted already.
    ///
    /// - Returns: `true` if permissions are granted (either already or after user approval),
    ///           `false` if permissions are denied or the dialog is dismissed
    ///
    /// ## Important
    /// Only call this method when you're ready to present the system permission dialog
    /// to the user. Consider using ``hasAccessibilityPermissions()`` first to check
    /// current permission status.
    @MainActor
    public static func askForAccessibilityIfNeeded() -> Bool {
        // Skip permission dialog in test environment
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
            ProcessInfo.processInfo.arguments.contains("--test-mode") ||
            NSClassFromString("XCTest") != nil
        {
            return false // Return false to indicate no permissions in test mode
        }
        let options = [CFConstants.axTrustedCheckOptionPrompt as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary?)
    }

    /// Checks if the app currently has accessibility permissions without prompting.
    ///
    /// Use this method to check permission status without triggering the system
    /// permission dialog.
    ///
    /// - Returns: `true` if accessibility permissions are granted, `false` otherwise
    @MainActor
    public static func hasAccessibilityPermissions() -> Bool {
        AXIsProcessTrusted()
    }

    /// Determines if the app is running in a sandboxed environment.
    ///
    /// This can be useful for adjusting behavior based on the app's security context,
    /// as sandboxed apps may have different accessibility permission requirements.
    ///
    /// - Returns: `true` if the app is sandboxed, `false` otherwise
    public static func isSandboxed() -> Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

    // MARK: - Modern Async/Await API

    /// Requests accessibility permissions asynchronously.
    ///
    /// This async version of permission requesting provides a more modern API
    /// for Swift concurrency environments. It will show the system permission
    /// prompt if permissions haven't been granted.
    ///
    /// - Returns: `true` if permissions are granted, `false` otherwise
    ///
    /// ## Example
    ///
    /// ```swift
    /// let hasPermissions = await AXPermissionHelpers.requestPermissions()
    /// if hasPermissions {
    ///     // Proceed with accessibility operations
    /// } else {
    ///     // Handle permission denial
    /// }
    /// ```
    ///
    /// > Important: This method will display the system permission dialog.
    /// > Only call it when appropriate for your user experience.
    public static func requestPermissions() async -> Bool {
        await MainActor.run {
            self.askForAccessibilityIfNeeded()
        }
    }

    /// Monitors accessibility permission changes as an AsyncStream.
    ///
    /// This method provides a reactive way to observe permission state changes
    /// over time, useful for updating UI or taking actions when permissions
    /// are granted or revoked.
    ///
    /// - Parameter interval: The polling interval in seconds (default: 1.0)
    /// - Returns: An ``AsyncStream<Bool>`` that emits permission status changes
    ///
    /// ## Example
    ///
    /// ```swift
    /// for await hasPermissions in AXPermissionHelpers.permissionChanges() {
    ///     if hasPermissions {
    ///         print("Permissions granted!")
    ///         // Enable accessibility features
    ///     } else {
    ///         print("Permissions revoked!")
    ///         // Disable accessibility features
    ///     }
    /// }
    /// ```
    ///
    /// > Note: The stream automatically cleans up its timer when cancelled.
    public static func permissionChanges(
        interval: TimeInterval = 1.0) -> AsyncStream<Bool>
    {
        self.permissionChanges(interval: interval, onTimerScheduled: nil)
    }

    nonisolated static func permissionChanges(
        interval: TimeInterval,
        onTimerScheduled: (@MainActor () -> Void)?) -> AsyncStream<Bool>
    {
        AsyncStream { continuation in
            // Use a class to hold the timer and state to avoid capture issues
            final class TimerBox: @unchecked Sendable {
                private let lock = NSLock()
                var timer: Timer?
                var lastState: Bool?
                private var terminatedFlag = false

                var isTerminated: Bool {
                    self.lock.lock()
                    defer { self.lock.unlock() }
                    return self.terminatedFlag
                }

                func markTerminated() {
                    self.lock.lock()
                    self.terminatedFlag = true
                    self.lock.unlock()
                }
            }
            let timerBox = TimerBox()

            let start: @MainActor () -> Void = {
                guard !timerBox.isTerminated else { return }
                let initialState = self.hasAccessibilityPermissions()
                timerBox.lastState = initialState
                continuation.yield(initialState)
                timerBox.timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
                    let currentState = MainActor.assumeIsolated {
                        self.hasAccessibilityPermissions()
                    }
                    if currentState != timerBox.lastState {
                        timerBox.lastState = currentState
                        continuation.yield(currentState)
                    }
                }
                onTimerScheduled?()
            }
            Self.hopToMainActor(start)

            continuation.onTermination = { @Sendable _ in
                timerBox.markTerminated()
                Self.hopToMainActor {
                    timerBox.timer?.invalidate()
                    timerBox.timer = nil
                }
            }
        }
    }

    @inline(__always)
    private nonisolated static func hopToMainActor(_ work: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated(work)
            return
        }
        DispatchQueue.main.async {
            MainActor.assumeIsolated(work)
        }
    }
}
