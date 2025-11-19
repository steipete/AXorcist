import AppKit

/// Lightweight wrapper around a running application that exposes common AX handles
/// without forcing callers to touch `AXUIElementCreateApplication` directly.
public struct AXApp: Sendable {
    public let application: NSRunningApplication
    public let element: Element

    public init(_ application: NSRunningApplication) {
        self.application = application
        self.element = Element(AXUIElementCreateApplication(application.processIdentifier))
    }

    /// Convenience initializer from a pid if the process is running.
    public init?(pid: pid_t) {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return nil }
        self.init(app)
    }

    public var pid: pid_t { application.processIdentifier }
    public var bundleIdentifier: String? { application.bundleIdentifier }
    public var localizedName: String? { application.localizedName }

    /// Windows exposed via AX for this application.
    public func windows() -> [Element]? {
        element.windows()
    }

    /// Focused window if available.
    public func focusedWindow() -> Element? {
        element.focusedWindow()
    }
}

/// Simple typed window handle pairing an AX element with its owning app.
public struct AXWindowHandle: Sendable {
    public let app: AXApp
    public let element: Element

    public init(app: AXApp, element: Element) {
        self.app = app
        self.element = element
    }

    public var title: String? { element.title() }
    public var frame: CGRect? { element.frame() }
    public var role: String? { element.role() }

    /// CGWindowID for this AX window, if resolvable.
    public var windowID: CGWindowID? {
        AXWindowResolver().windowID(from: element)
    }
}
