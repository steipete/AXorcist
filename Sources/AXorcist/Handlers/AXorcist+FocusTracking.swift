import AppKit // For pid_t, AXObserver, AXUIElement, kAXFocusedUIElementChangedNotification etc.
import ApplicationServices
// GlobalAXLogger is used instead of OSLog

// MARK: - Focus Tracking Handlers
extension AXorcist {
    // Public typealias for the callback
    public typealias AXFocusChangeCallback = @MainActor (_ focusedElement: AXUIElement, _ pid: pid_t) -> Void

    // Internal properties to manage the observer
    // These need to be associated with the AXorcist instance.
    // Swift extension cannot have stored properties. This needs a different approach.
    // Option 1: Use a shared static dictionary keyed by AXorcist instance hash or a unique ID.
    // Option 2: Make AXorcist a class and add these as instance properties (preferred if AXorcist is already a class).
    // AXorcist IS a class, so we can add these there.

    // MOVED to AXorcist.swift main class body:
    // internal var focusTrackingObserver: AXObserver?
    // internal var focusTrackingPID: pid_t = 0
    // internal var focusTrackingCallback: AXFocusChangeCallback?
    // internal var focusSystemWideObserver: AXObserver? // For system-wide focus (more complex)

    @MainActor
    public func startFocusTracking(
        for pid: pid_t,
        callback: @escaping AXFocusChangeCallback
    ) -> Bool {
        axDebugLog("Attempting to start focus tracking for PID \(pid).")

        if self.focusTrackingObserver != nil {
            axInfoLog("Focus tracking already active for PID \(self.focusTrackingPID). Stopping first.")
            _ = stopFocusTracking()
        }

        self.focusTrackingPID = pid
        self.focusTrackingCallback = callback
        var observer: AXObserver?

        let observerCallback: AXObserverCallback = { _, element, notification, refcon in
            guard let refcon = refcon else { return }
            let axorcistInstance = Unmanaged<AXorcist>.fromOpaque(refcon).takeUnretainedValue()

            var eventPID: pid_t = 0
            AXUIElementGetPid(element, &eventPID)

            var actualFocusedElement: AXUIElement = element
            // Compare notification with CFString directly
            if (notification as CFString) == kAXFocusedWindowChangedNotification as CFString {
                var focusedElementForWindowChange: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, kAXFocusedUIElementAttribute as CFString, &focusedElementForWindowChange) == .success,
                   let focusedRef = focusedElementForWindowChange {
                    actualFocusedElement = focusedRef as! AXUIElement // ARC handles focusedRef
                } else {
                    axDebugLog("Could not get focused element on window change, using app element.")
                }
            }

            axorcistInstance.focusTrackingCallback?(actualFocusedElement, eventPID)
            // CFRelease for actualFocusedElement (if it was a copy) is handled by ARC.
        }

        let error = AXObserverCreate(pid, observerCallback, &observer)
        if error == .success, let newObserver = observer {
            self.focusTrackingObserver = newObserver
            let selfPtr = Unmanaged.passUnretained(self).toOpaque()
            let appElement = AXUIElementCreateApplication(pid) // ARC manages appElement

            AXObserverAddNotification(newObserver, appElement, kAXFocusedUIElementChangedNotification as CFString, selfPtr)
            AXObserverAddNotification(newObserver, appElement, kAXFocusedWindowChangedNotification as CFString, selfPtr)

            CFRunLoopAddSource(RunLoop.current.getCFRunLoop(), AXObserverGetRunLoopSource(newObserver), .defaultMode)
            axInfoLog("Successfully started focus tracking for PID \(pid).")
            return true
        } else {
            axErrorLog("Error starting focus tracking for PID \(pid): \(error.rawValue)")
            self.focusTrackingObserver = nil
            self.focusTrackingPID = 0
            self.focusTrackingCallback = nil
            return false
        }
    }

    @MainActor
    public func stopFocusTracking() -> Bool {
        guard let observer = self.focusTrackingObserver else {
            axInfoLog("Focus tracking not active, no observer to stop.")
            return true
        }

        CFRunLoopRemoveSource(RunLoop.current.getCFRunLoop(), AXObserverGetRunLoopSource(observer), .defaultMode)
        // AXObserverInvalidate(observer) // Consider if observer is not deallocated automatically.

        self.focusTrackingObserver = nil
        self.focusTrackingPID = 0
        self.focusTrackingCallback = nil
        axInfoLog("Successfully stopped focus tracking.")
        return true
    }
}
