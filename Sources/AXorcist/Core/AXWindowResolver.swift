import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import os

/// Generic window/App resolution helpers (no product heuristics).
public final class AXWindowResolver {
    private let logger = Logger(subsystem: "boo.peekaboo.axorcist", category: "AXWindowResolver")

    public init() {}

    // MARK: - CGWindowID extraction

    /// Private API to extract CGWindowID from an AXUIElement.
    @_silgen_name("_AXUIElementGetWindow")
    private func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: inout CGWindowID) -> AXError

    /// Extract CGWindowID from an AXUIElement window.
    @MainActor
    public func windowID(from axElement: AXUIElement) -> CGWindowID? {
        var windowID: CGWindowID = 0
        let result = _AXUIElementGetWindow(axElement, &windowID)
        guard result == .success else {
            self.logger.error("Failed to get window ID from AXUIElement, error: \(result.rawValue)")
            return nil
        }
        return windowID
    }

    /// Extract CGWindowID from an AXorcist Element.
    @MainActor
    public func windowID(from element: Element) -> CGWindowID? {
        let axElement = element.underlyingElement
        return self.windowID(from: axElement)
    }

    // MARK: - Lookup

    /// Find AX window by CGWindowID in a specific app.
    @MainActor
    public func findWindow(by windowID: CGWindowID, in app: NSRunningApplication) -> Element? {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        let element = Element(appElement)
        guard let windows = element.windows() else { return nil }

        for window in windows {
            if let currentID = self.windowID(from: window), currentID == windowID {
                return window
            }
        }
        return nil
    }

    /// Find AX window by CGWindowID across running apps.
    @MainActor
    public func findWindow(by windowID: CGWindowID) -> (window: Element, app: NSRunningApplication)? {
        // Fast path: CoreGraphics owner lookup
        let options: CGWindowListOption = [.optionIncludingWindow]
        if let windowInfoList = CGWindowListCopyWindowInfo(options, windowID) as? [[String: Any]],
           let windowInfo = windowInfoList.first,
           let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? pid_t,
           let app = NSWorkspace.shared.runningApplications.first(where: { $0.processIdentifier == ownerPID }),
           let window = self.findWindow(by: windowID, in: app)
        {
            return (window, app)
        }

        // Fallback: full AX enumeration (works without Screen Recording permission).
        for app in NSWorkspace.shared.runningApplications {
            if let window = self.findWindow(by: windowID, in: app) {
                return (window, app)
            }
        }

        return nil
    }

    // MARK: - Window info

    public struct WindowInfo: Sendable {
        public let windowID: CGWindowID
        public let title: String?
        public let bounds: CGRect
        public let ownerPID: pid_t
        public let applicationName: String?
        public let bundleIdentifier: String?
        public let layer: Int
        public let alpha: CGFloat
    }

    /// Get comprehensive window information using CGWindowID.
    public func windowInfo(windowID: CGWindowID) -> WindowInfo? {
        let options: CGWindowListOption = [.optionIncludingWindow]
        guard let windowInfoList = CGWindowListCopyWindowInfo(options, windowID) as? [[String: Any]],
              let info = windowInfoList.first
        else {
            return nil
        }

        let title = info[kCGWindowName as String] as? String
        let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t ?? 0
        let layer = info[kCGWindowLayer as String] as? Int ?? 0
        let alpha = info[kCGWindowAlpha as String] as? CGFloat ?? 1.0

        var bounds: CGRect = .zero
        if let boundsDict = info[kCGWindowBounds as String] as? [String: Any] {
            bounds = CGRect(
                x: boundsDict["X"] as? CGFloat ?? 0,
                y: boundsDict["Y"] as? CGFloat ?? 0,
                width: boundsDict["Width"] as? CGFloat ?? 0,
                height: boundsDict["Height"] as? CGFloat ?? 0)
        }

        let app = NSWorkspace.shared.runningApplications
            .first(where: { $0.processIdentifier == ownerPID })

        return WindowInfo(
            windowID: windowID,
            title: title,
            bounds: bounds,
            ownerPID: ownerPID,
            applicationName: app?.localizedName,
            bundleIdentifier: app?.bundleIdentifier,
            layer: layer,
            alpha: alpha)
    }

    // MARK: - Existence

    public func windowExists(windowID: CGWindowID) -> Bool {
        self.windowInfo(windowID: windowID) != nil
    }
}
