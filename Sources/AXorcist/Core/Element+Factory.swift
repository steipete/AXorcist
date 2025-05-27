// Element+Factory.swift - Factory methods for creating Element instances

import ApplicationServices
import AppKit

// MARK: - Static Factory Methods for System-Wide and Application Elements
extension Element {
    @MainActor
    public static func systemWide() -> Element {
        return Element(AXUIElementCreateSystemWide())
    }

    @MainActor
    public static func application(for pid: pid_t) -> Element? {
        let appElementRef = AXUIElementCreateApplication(pid)
        let testElement = Element(appElementRef)
        // A basic check to see if the application element is valid (e.g., by trying to get its role)
        if testElement.role() != nil { // role() is synchronous
            return testElement
        }
        GlobalAXLogger.shared.log(AXLogEntry(
            level: .warning,
            message: "Failed to create a valid application Element for PID \(pid). Role check failed."
        ))
        return nil
    }

    @MainActor
    public static func application(for runningApp: NSRunningApplication) -> Element? {
        return application(for: runningApp.processIdentifier)
    }

    @MainActor
    public static func focusedApplication() -> Element? {
        guard let focusedApp = NSWorkspace.shared.frontmostApplication else {
            GlobalAXLogger.shared.log(AXLogEntry(
                level: .warning,
                message: "No frontmost application could be determined."
            ))
            return nil
        }
        return application(for: focusedApp)
    }

    /// Gets the element at the specified position (system-wide)
    @MainActor
    public static func elementAtPoint(_ point: CGPoint, pid: pid_t = 0) -> Element? {
        if pid != 0 {
            // Use specific application if PID is provided
            guard let appElement = application(for: pid) else {
                axDebugLog("Failed to get application element for PID \(pid)")
                return nil
            }
            return AXUIElement.elementAtPosition(
                in: appElement.underlyingElement,
                x: Float(point.x),
                y: Float(point.y)
            ).map(Element.init)
        } else {
            // System-wide element at point
            var element: AXUIElement?
            let error = AXUIElementCopyElementAtPosition(
                AXUIElementCreateSystemWide(),
                Float(point.x),
                Float(point.y),
                &element
            )

            if error == .success, let element = element {
                return Element(element)
            }
            return nil
        }
    }
}
