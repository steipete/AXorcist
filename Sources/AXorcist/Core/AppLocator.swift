import AppKit
import CoreGraphics
import Foundation
import os

/// Generic helpers for discovering running applications.
public enum AppLocator {
    private static let logger = Logger(subsystem: "boo.peekaboo.axorcist", category: "AppLocator")

    /// Find the application that owns the window under the given screen point.
    /// Falls back to the frontmost app if nothing matches.
    @MainActor
    public static func app(at screenPoint: CGPoint? = nil) -> NSRunningApplication? {
        let mouseLocation = screenPoint ?? NSEvent.mouseLocation

        // Prefer frontmost app first (cheap).
        if let front = NSWorkspace.shared.frontmostApplication,
           Self.point(mouseLocation, isInsideWindowOf: front) {
            return front
        }

        // Search other visible apps.
        let visibleApps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isHidden && $0.bundleIdentifier != nil
        }

        for app in visibleApps {
            if Self.point(mouseLocation, isInsideWindowOf: app) {
                return app
            }
        }

        // Fallback.
        let fallback = NSWorkspace.shared.frontmostApplication
        Self.logger.debug("app(at:): falling back to frontmost \(fallback?.localizedName ?? "unknown")")
        return fallback
    }

    @MainActor
    private static func point(_ point: CGPoint, isInsideWindowOf app: NSRunningApplication) -> Bool {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        let appElement = Element(axApp)
        guard let windows = appElement.windows() else { return false }
        for window in windows {
            if let frame = window.frame(), frame.contains(point) {
                return true
            }
        }
        return false
    }
}
