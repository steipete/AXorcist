import AppKit
import CoreGraphics
import Foundation
import os

/// Generic helpers for discovering running applications.
public enum AppLocator {
    private static let logger = Logger(subsystem: "boo.peekaboo.axorcist", category: "AppLocator")

    enum ResolutionPolicy: Sendable {
        case exact
        case frontmostCompatibility
    }

    struct WindowSnapshot: Equatable, Sendable {
        let ownerPID: pid_t
        let bounds: CGRect
    }

    struct ScreenCoordinateSpace: Equatable, Sendable {
        let appKitFrame: CGRect
        let quartzFrame: CGRect
    }

    struct ApplicationLookup<Application> {
        let applicationForPID: (pid_t) -> Application?
        let isEligible: (Application) -> Bool
        let frontmostApplication: () -> Application?
    }

    /// Find the application that owns an on-screen window under the given screen point.
    ///
    /// This exact lookup never substitutes the frontmost application when the point does not match. Callers with an
    /// explicit PID or application selector should resolve that selector directly instead of broadening the request to
    /// a spatial lookup.
    ///
    /// - Parameter screenPoint: A point in Quartz global screen coordinates. When omitted, the current AppKit mouse
    ///   location is translated into the matching display's Quartz coordinate space.
    @MainActor
    public static func exactApp(at screenPoint: CGPoint? = nil) -> NSRunningApplication? {
        self.locate(at: screenPoint, policy: .exact)
    }

    /// Compatibility lookup for legacy pointer workflows.
    ///
    /// If no on-screen window matches the point, this method preserves the historical behavior of returning the
    /// frontmost application. Use ``exactApp(at:)`` when a miss must remain a miss.
    @MainActor
    public static func app(at screenPoint: CGPoint? = nil) -> NSRunningApplication? {
        self.locate(at: screenPoint, policy: .frontmostCompatibility)
    }

    @MainActor
    private static func locate(
        at screenPoint: CGPoint?,
        policy: ResolutionPolicy) -> NSRunningApplication?
    {
        let mouseLocation = screenPoint ?? self.currentMouseLocationInQuartzCoordinates()
        let windows = self.onScreenWindowSnapshots()

        return self.locate(
            at: mouseLocation,
            windows: windows,
            policy: policy,
            applications: ApplicationLookup(
                applicationForPID: { NSRunningApplication(processIdentifier: $0) },
                isEligible: {
                    $0.activationPolicy == .regular && !$0.isHidden && $0.bundleIdentifier != nil
                },
                frontmostApplication: {
                    let fallback = NSWorkspace.shared.frontmostApplication
                    Self.logger.debug("app(at:): falling back to frontmost \(fallback?.localizedName ?? "unknown")")
                    return fallback
                }))
    }

    @MainActor
    static func locate<Application>(
        at point: CGPoint,
        windows: [WindowSnapshot],
        policy: ResolutionPolicy,
        applications: ApplicationLookup<Application>) -> Application?
    {
        var inspectedPIDs: Set<pid_t> = []
        for window in windows {
            guard window.bounds.contains(point),
                  inspectedPIDs.insert(window.ownerPID).inserted,
                  let application = applications.applicationForPID(window.ownerPID),
                  applications.isEligible(application)
            else { continue }

            return application
        }

        switch policy {
        case .exact:
            return nil
        case .frontmostCompatibility:
            return applications.frontmostApplication()
        }
    }

    private static func onScreenWindowSnapshots() -> [WindowSnapshot] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowInfo = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        return windowInfo.compactMap { info in
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let x = bounds["X"] as? CGFloat,
                  let y = bounds["Y"] as? CGFloat,
                  let width = bounds["Width"] as? CGFloat,
                  let height = bounds["Height"] as? CGFloat
            else { return nil }

            return WindowSnapshot(
                ownerPID: ownerPID,
                bounds: CGRect(x: x, y: y, width: width, height: height))
        }
    }

    @MainActor
    private static func currentMouseLocationInQuartzCoordinates() -> CGPoint {
        let point = NSEvent.mouseLocation
        let screens = NSScreen.screens.compactMap { screen -> ScreenCoordinateSpace? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }

            return ScreenCoordinateSpace(
                appKitFrame: screen.frame,
                quartzFrame: CGDisplayBounds(CGDirectDisplayID(number.uint32Value)))
        }
        return self.quartzPoint(fromAppKit: point, screens: screens) ?? point
    }

    static func quartzPoint(
        fromAppKit point: CGPoint,
        screens: [ScreenCoordinateSpace]) -> CGPoint?
    {
        guard let screen = screens.first(where: { $0.appKitFrame.contains(point) }) else { return nil }
        let localX = point.x - screen.appKitFrame.minX
        let localY = point.y - screen.appKitFrame.minY
        return CGPoint(
            x: screen.quartzFrame.minX + localX,
            y: screen.quartzFrame.minY + screen.quartzFrame.height - localY)
    }
}
