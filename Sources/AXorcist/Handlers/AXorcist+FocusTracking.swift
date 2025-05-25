import AppKit // For pid_t, AXObserver, AXUIElement, kAXFocusedUIElementChangedNotification etc.
import ApplicationServices
// GlobalAXLogger is used instead of OSLog

// MARK: - Focus Tracking Handlers
extension AXorcist {
    // Public typealias for the callback
    public typealias AXFocusChangeCallback = @MainActor (_ focusedElement: Element, _ pid: pid_t, _ notification: AXNotification) -> Void

    // MARK: - New Implementation using AXObserverCenter

    @MainActor
    public func startFocusTracking(
        for pid: pid_t,
        callback: @escaping AXFocusChangeCallback
    ) -> Bool {
        axDebugLog("Attempting to start focus tracking for PID \(pid).")

        // Stop existing tracking if any
        if self.focusTrackingPID != 0 || self.focusedUIElementToken != nil || self.focusedWindowToken != nil {
            axInfoLog("Focus tracking potentially active (PID \(self.focusTrackingPID), UI token: \(self.focusedUIElementToken != nil), Window token: \(self.focusedWindowToken != nil)). Stopping first.")
            _ = stopFocusTracking() // Ensure any previous tracking is fully stopped
        }

        self.focusTrackingPID = pid
        self.focusTrackingCallback = callback

        var success = true

        // Subscribe to Focused UI Element Changed
        let focusedUIElementResult = AXObserverCenter.shared.subscribe(
            pid: pid,
            notification: .focusedUIElementChanged
        ) { [weak self] eventPid, axNotification, rawElement, _ in
            guard let self = self, let cb = self.focusTrackingCallback else {
                axWarningLog("Focus tracking callback or self is nil for .focusedUIElementChanged. PID: \(eventPid)")
                return
            }
            let focusedElement = Element(rawElement)
            cb(focusedElement, eventPid, axNotification)
            axDebugLog("Focus tracking: .focusedUIElementChanged. Element: \(focusedElement.briefDescription()), PID: \(eventPid), Notification: \(axNotification.rawValue)")
        }

        if case .success(let token) = focusedUIElementResult {
            self.focusedUIElementToken = token
            axInfoLog("Successfully subscribed to .focusedUIElementChanged for PID \(pid). Token: \(token.id)")
        } else if case .failure(let error) = focusedUIElementResult {
            axErrorLog("Failed to subscribe to .focusedUIElementChanged for PID \(pid). Error: \(error.localizedDescription)")
            success = false
        }

        // Subscribe to Focused Window Changed
        let focusedWindowResult = AXObserverCenter.shared.subscribe(
            pid: pid,
            notification: .focusedWindowChanged
        ) { [weak self] eventPid, axNotification, rawWindowElement, nsUserInfo in
            guard let self = self, let cb = self.focusTrackingCallback else {
                axWarningLog("Focus tracking callback or self is nil for .focusedWindowChanged. PID: \(eventPid)")
                return
            }
            let windowElement = Element(rawWindowElement)
            var actualFocusedElement: Element = windowElement
            if let uiInfo = nsUserInfo, let focusedCF = uiInfo[AXMiscConstants.focusedUIElementKey] {
                if CFGetTypeID(focusedCF as CFTypeRef) == AXUIElementGetTypeID() {
                    actualFocusedElement = Element(focusedCF as! AXUIElement)
                } else {
                    axWarningLog("userInfo contained kAXFocusedUIElementKey but it was not an AXUIElement. Type: \(CFGetTypeID(focusedCF as CFTypeRef))")
                }
            } else if let focusedEl = windowElement.focusedUIElement() {
                actualFocusedElement = focusedEl
            }
            cb(actualFocusedElement, eventPid, axNotification)
            axDebugLog("Focus tracking: .focusedWindowChanged. Actual Element: \(actualFocusedElement.briefDescription()), PID: \(eventPid), Notification: \(axNotification.rawValue)")
        }

        if case .success(let token) = focusedWindowResult {
            self.focusedWindowToken = token
            axInfoLog("Successfully subscribed to .focusedWindowChanged for PID \(pid). Token: \(token.id)")
        } else if case .failure(let error) = focusedWindowResult {
            axErrorLog("Failed to subscribe to .focusedWindowChanged for PID \(pid). Error: \(error.localizedDescription)")
            success = false
        }

        if success {
            axInfoLog("Successfully started focus tracking for PID \(pid).")
        } else {
            axErrorLog("Error starting focus tracking for PID \(pid). Cleaning up.")
            _ = stopFocusTracking() // Clean up any partial subscriptions
        }
        return success
    }

    @MainActor
    public func stopFocusTracking() -> Bool {
        guard self.focusTrackingPID != 0 || self.focusedUIElementToken != nil || self.focusedWindowToken != nil || self.systemWideFocusToken != nil else {
            axInfoLog("Focus tracking not active (no PID or tokens).")
            return true
        }

        axInfoLog("Attempting to stop focus tracking for PID \(self.focusTrackingPID). UI Token: \(self.focusedUIElementToken != nil), Window Token: \(self.focusedWindowToken != nil), System Token: \(self.systemWideFocusToken != nil)")

        var allSuccess = true

        if let token = self.focusedUIElementToken {
            do {
                try AXObserverCenter.shared.unsubscribe(token: token)
                axInfoLog("Unsubscribed from .focusedUIElementChanged. PID: \(self.focusTrackingPID)")
                self.focusedUIElementToken = nil
            } catch {
                axErrorLog("Failed to unsubscribe from .focusedUIElementChanged for PID \(self.focusTrackingPID): \(error)")
                allSuccess = false
            }
        }

        if let token = self.focusedWindowToken {
            do {
                try AXObserverCenter.shared.unsubscribe(token: token)
                axInfoLog("Unsubscribed from .focusedWindowChanged. PID: \(self.focusTrackingPID)")
                self.focusedWindowToken = nil
            } catch {
                axErrorLog("Failed to unsubscribe from .focusedWindowChanged for PID \(self.focusTrackingPID): \(error)")
                allSuccess = false
            }
        }

        if let token = self.systemWideFocusToken {
            do {
                try AXObserverCenter.shared.unsubscribe(token: token)
                axInfoLog("Unsubscribed from system-wide focus tracking.")
                self.systemWideFocusToken = nil
            } catch {
                axErrorLog("Failed to unsubscribe from system-wide focus tracking: \(error)")
                allSuccess = false
            }
        }

        self.focusTrackingPID = 0 // Reset PID regardless of unsubscribe success
        self.focusTrackingCallback = nil
        // focusTrackingObserver is not used with AXObserverCenter

        if allSuccess {
            axInfoLog("Successfully stopped all focus tracking subscriptions.")
        } else {
            axWarningLog("Encountered errors while stopping focus tracking subscriptions.")
        }
        return allSuccess
    }

    // MARK: - System-wide Focus Tracking

    @MainActor
    public func startSystemWideFocusTracking(callback: @escaping AXFocusChangeCallback) -> Bool {
        axDebugLog("Attempting to start system-wide focus tracking.")

        // Stop existing tracking if any
        if self.systemWideFocusToken != nil {
            axInfoLog("System-wide focus tracking already active. Stopping first.")
            _ = stopFocusTracking() // stopFocusTracking will handle systemWideFocusToken
        }

        // Ensure other PID-specific tracking is also stopped
        if self.focusTrackingPID != 0 {
            axInfoLog("PID-specific focus tracking active (PID \(self.focusTrackingPID)). Stopping it as well.")
            _ = stopFocusTracking()
        }

        self.focusTrackingCallback = callback // Store the callback

        let systemWideResult = AXObserverCenter.shared.subscribe(
            pid: nil, // System-wide
            notification: .focusedApplicationChanged
        ) { [weak self] eventPid, axNotification, rawAppElement, _ in
            guard let self = self, let cb = self.focusTrackingCallback else {
                axWarningLog("System-wide focus tracking callback or self is nil for .focusedApplicationChanged. PID: \(eventPid)")
                return
            }
            let appElement = Element(rawAppElement)
            var actualFocusedElement: Element = appElement
            if let focusedUI = appElement.focusedUIElement() {
                actualFocusedElement = focusedUI
            }
            cb(actualFocusedElement, eventPid, axNotification)
            axDebugLog("System-wide focus tracking: .focusedApplicationChanged. Actual Element: \(actualFocusedElement.briefDescription()), PID: \(eventPid), Notification: \(axNotification.rawValue)")
        }

        switch systemWideResult {
        case .success(let token):
            self.systemWideFocusToken = token
            axInfoLog("Successfully subscribed to system-wide .focusedApplicationChanged. Token: \(token.id)")
            return true
        case .failure(let error):
            axErrorLog("Failed to subscribe to system-wide .focusedApplicationChanged. Error: \(error.localizedDescription)")
            return false
        }
    }

    @MainActor
    public func stopSystemWideFocusTracking() -> Bool {
        axDebugLog("Attempting to stop system-wide focus tracking (will call general stopFocusTracking).")
        // stopFocusTracking() already handles the systemWideFocusToken
        return stopFocusTracking()
    }
}
