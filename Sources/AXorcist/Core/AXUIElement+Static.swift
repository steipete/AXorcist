//
//  AXUIElement+Static.swift
//  AXorcist
//
//  Static factory methods and convenience functions for AXUIElement
//

import ApplicationServices
import Foundation
#if canImport(AppKit)
    import AppKit
#endif

extension AXUIElement {
    // MARK: - Static Factory Methods

    /// Returns the system-wide accessibility object
    public static var systemWide: AXUIElement {
        return AXUIElementCreateSystemWide()
    }

    /// Creates an application accessibility object for the given process ID
    public static func application(pid: pid_t) -> AXUIElement {
        return AXUIElementCreateApplication(pid)
    }

    /// Returns the currently focused application
    @MainActor
    public static func focusedApplication() throws -> AXUIElement {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedApp: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(systemWideElement, AXAttributeNames.kAXFocusedApplicationAttribute as CFString, &focusedApp)

        guard error == .success, let app = focusedApp, CFGetTypeID(app) == AXUIElementGetTypeID() else {
            let errorDetails = "AXError: \(error.rawValue) - \(error.localizedDescription)"
            axErrorLog("Failed to get focused application: \(errorDetails)")
            throw AccessibilityError.attributeNotReadable(attribute: AXAttributeNames.kAXFocusedApplicationAttribute, elementDescription: "SystemWideElement")
        }
        return app as! AXUIElement
    }

    /// Returns the frontmost application using NSWorkspace
    public static func frontmostApplication() -> AXUIElement? {
        #if canImport(AppKit)
            guard let app = NSWorkspace.shared.frontmostApplication else {
                return nil
            }
            return AXUIElement.application(pid: app.processIdentifier)
        #else
            // Fallback to focused application on non-AppKit platforms
            return focusedApplication()
        #endif
    }

    /// Gets the element at the specified position within an application
    @MainActor
    public static func elementAtPosition(
        in app: AXUIElement,
        x: Float,
        y: Float
    ) -> AXUIElement? {
        var element: AXUIElement?
        let error = AXUIElementCopyElementAtPosition(app, x, y, &element)

        if error == .success {
            return element
        } else {
            axDebugLog("Failed to get element at position (\(x), \(y)): \(error.rawValue)")
            return nil
        }
    }

    // MARK: - Window-related static methods

    /// Returns the focused window in the focused application
    @MainActor
    public static func focusedWindowInFocusedApplication() -> AXUIElement? {
        guard let app = try? AXUIElement.focusedApplication() else { return nil }
        return AXUIElement.focusedWindow(in: app)
    }

    /// Returns the focused window in the frontmost application
    @MainActor
    public static func focusedWindowInFrontmostApplication() -> AXUIElement? {
        guard let app = AXUIElement.frontmostApplication() else { return nil }
        return AXUIElement.focusedWindow(in: app)
    }

    /// Returns the focused window in the specified application
    @MainActor
    public static func focusedWindow(in app: AXUIElement) -> AXUIElement? {
        var focusedWindow: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(app, AXAttributeNames.kAXFocusedWindowAttribute as CFString, &focusedWindow)

        guard error == .success,
              let window = focusedWindow,
              CFGetTypeID(window) == AXUIElementGetTypeID() else {
            return nil
        }

        return (window as! AXUIElement)
    }

    /// Returns the main window in the frontmost application
    @MainActor
    public static func mainWindowInFrontmostApplication() -> AXUIElement? {
        guard let app = AXUIElement.frontmostApplication() else { return nil }
        return AXUIElement.mainWindow(in: app)
    }

    /// Returns the main window in the specified application
    @MainActor
    public static func mainWindow(in app: AXUIElement) -> AXUIElement? {
        var mainWindow: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(app, AXAttributeNames.kAXMainWindowAttribute as CFString, &mainWindow)

        guard error == .success,
              let window = mainWindow,
              CFGetTypeID(window) == AXUIElementGetTypeID() else {
            return nil
        }

        return (window as! AXUIElement)
    }

    /// Returns all windows for the specified application
    @MainActor
    public static func windows(for app: AXUIElement) -> [AXUIElement]? {
        var windows: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(app, AXAttributeNames.kAXWindowsAttribute as CFString, &windows)

        guard error == .success,
              let windowArray = windows,
              CFGetTypeID(windowArray) == CFArrayGetTypeID() else {
            return nil
        }

        return (windowArray as? [AXUIElement])
    }

    /// Returns all windows for the specified process ID
    @MainActor
    public static func windows(for pid: pid_t) -> [AXUIElement]? {
        let app = AXUIElement.application(pid: pid)
        return AXUIElement.windows(for: app)
    }
}
