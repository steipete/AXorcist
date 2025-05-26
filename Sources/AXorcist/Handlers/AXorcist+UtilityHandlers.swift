import AppKit // Required for NSScreen, CGPoint, pid_t
import ApplicationServices
import CoreGraphics // Ensure CGPoint is available for parameter type
import Foundation
// GlobalAXLogger should be available

// MARK: - Utility Handlers
extension AXorcist {

    /// Fetches basic identifying information (role and title) for a given accessibility element.
    /// This is useful for creating preview strings for elements referenced by attributes.
    ///
    /// - Parameters:
    ///   - element: The `AXUIElement` to get information for.
    /// - Returns: A tuple containing the preview string (or nil) and an array of debug log messages.
    @MainActor
    public func getPreviewString(
        forElement axElement: AXUIElement?
    ) -> String? {
        guard let axUIElement = axElement else {
            axDebugLog("getPreviewString: Element is nil.")
            return nil
        }

        let element = Element(axUIElement)
        let role = element.role()
        let title = element.title()

        axDebugLog("getPreviewString: Fetched Role=\'\(role ?? "<nil>")\', Title=\'\(title ?? "<nil>")\' for element.")

        if let roleValue = role, !roleValue.isEmpty, let titleValue = title, !titleValue.isEmpty {
            return "\(roleValue): \(titleValue)"
        } else if let roleValue = role, !roleValue.isEmpty {
            return roleValue
        } else if let titleValue = title, !titleValue.isEmpty {
            return titleValue
        } else {
            return "<AXUIElement>"
        }
    }

    /// Gets the accessibility element at a given screen point for a specific application.
    ///
    /// - Parameters:
    ///   - point: The screen point to hit-test. Its coordinate system origin (bottom-left or top-left)
    ///            is determined by `isScreenCoordinatesTopLeft`.
    ///   - pid: The process identifier of the target application.
    ///   - isScreenCoordinatesTopLeft: If `true`, `point` is assumed to have (0,0) at top-left of the screen.
    ///                                If `false` (default), `point` is assumed to be AppKit-style (bottom-left is (0,0))
    ///                                and will be converted internally.
    ///   - isDebugLoggingEnabled: Whether to enable debug logging.
    ///   - currentDebugLogs: An inout array for debug logs.
    /// - Returns: An `AXUIElement` if found, otherwise `nil`. The caller is responsible for releasing this element if non-nil.
    @MainActor
    public func getElementAtPoint(
        pid explicitPID: pid_t? = nil,
        point: CGPoint,
        appIdentifierOrNil: String? = nil, // Can be bundle ID or app name
        requestedAttributes: [String]? = nil,
        isScreenCoordinatesTopLeft: Bool = false
    ) async -> HandlerResponse {

        var targetPID: pid_t = 0
        var appElementForPath: Element?

        if let explicitPID = explicitPID, explicitPID > 0 {
            targetPID = explicitPID
            axDebugLog("getElementAtPoint: Using explicit PID: \(targetPID)")
        } else if let appID = appIdentifierOrNil {
            if let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: appID).first {
                targetPID = runningApp.processIdentifier
                axDebugLog("getElementAtPoint: Found running app by bundle ID '\(appID)', PID: \(targetPID)")
            } else if let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: appID.contains(".app") ? appID : "\(appID).app").first { // Try adding .app
                targetPID = runningApp.processIdentifier
                axDebugLog("getElementAtPoint: Found running app by bundle ID '\(appID).app', PID: \(targetPID)")
            } else if let pidInt = Int(appID), let runningApp = NSRunningApplication(processIdentifier: pid_t(pidInt)) {
                targetPID = runningApp.processIdentifier // Validates PID and gets consistent pid_t
                axDebugLog("getElementAtPoint: Using PID from appIdentifier string '\(appID)': \(targetPID)")
            } else {
                // Fallback to finding app by name (less reliable)
                let apps = NSWorkspace.shared.runningApplications.filter { $0.localizedName?.localizedCaseInsensitiveContains(appID) == true || $0.bundleIdentifier == appID }
                if let firstMatch = apps.first {
                    targetPID = firstMatch.processIdentifier
                    axDebugLog("getElementAtPoint: Found app by name/fallback '\(appID)', PID: \(targetPID)")
                } else {
                    let errorMsg = "getElementAtPoint: Could not determine PID from appIdentifier: \(appID)"
                    axErrorLog(errorMsg)
                    return HandlerResponse(error: errorMsg)
                }
            }
        } else { // No explicitPID and no appIdentifierOrNil, try focused app
            guard let focusedApp = NSWorkspace.shared.frontmostApplication else {
                let errorMsg = "getElementAtPoint: No PID or appIdentifier provided, and could not get focused application."
                axErrorLog(errorMsg)
                return HandlerResponse(error: errorMsg)
            }
            targetPID = focusedApp.processIdentifier
            axDebugLog("getElementAtPoint: No PID/appIdentifier, using focused app PID: \(targetPID) (\(focusedApp.localizedName ?? "Unknown"))")
        }

        if targetPID == 0 { // Still no valid PID
            let errorMsg = "getElementAtPoint: Failed to resolve a valid application PID."
            axErrorLog(errorMsg)
            return HandlerResponse(error: errorMsg)
        }

        let systemWideAppElement = AXUIElementCreateApplication(targetPID)
        appElementForPath = Element(systemWideAppElement) // For path generation later
        var finalY = Float(point.y)

        if !isScreenCoordinatesTopLeft {
            guard let mainScreen = NSScreen.main else {
                let errorMsg = "getElementAtPoint: Cannot get main screen info for coordinate conversion."
                axWarningLog(errorMsg)
                return HandlerResponse(error: errorMsg)
            }
            let screenHeight = Float(mainScreen.frame.height)
            finalY = screenHeight - Float(point.y)
            axDebugLog("getElementAtPoint: Converted point from (\(point.x), \(point.y)) to (\(point.x), \(finalY)) for AX top-left system.")
        } else {
            axDebugLog("getElementAtPoint: Using provided point (\(point.x), \(finalY)) as top-left screen coordinates.")
        }

        var hitTestElementRef: AXUIElement?
        let error = AXUIElementCopyElementAtPosition(systemWideAppElement, Float(point.x), finalY, &hitTestElementRef)

        if error == .success, let rawElement = hitTestElementRef {
            let foundElement = Element(rawElement)
            axDebugLog("getElementAtPoint: Successfully found element at (\(Float(point.x))), \(finalY)). Element: \(foundElement.briefDescription())")

            // Call the global getElementAttributes function
            let (attributes, _) = await getElementAttributes(
                element: foundElement,
                attributes: requestedAttributes ?? AXorcist.defaultAttributesToFetch,
                outputFormat: .jsonString, // Using jsonString format
                valueFormatOption: .smart // Assuming default options
            )
            let pathArray = appElementForPath != nil ? foundElement.generatePathArray(upTo: appElementForPath!) : foundElement.generatePathArray()
            let axElement = AXElement(attributes: attributes, path: pathArray)
            return HandlerResponse(data: AnyCodable(axElement))
        } else {
            let errorMsg = "getElementAtPoint: No element found at (\(Float(point.x))), \(finalY)). Error: \(error.rawValue)"
            axDebugLog(errorMsg)
            return HandlerResponse(error: errorMsg)
        }
    }
}
