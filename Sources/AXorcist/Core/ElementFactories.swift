// ElementFactories.swift - Factory functions for creating Element instances

import ApplicationServices // For AXUIElement and other C APIs
import Foundation

// Convenience factory for the application element - already @MainActor
@MainActor
public func applicationElement(for bundleIdOrName: String) -> Element? {
    // pid() is assumed to be refactored to use GlobalAXLogger or handle its own logging.
    guard let pid = pid(forAppIdentifier: bundleIdOrName) else {
        axWarningLog("applicationElement: Failed to obtain PID for '\(bundleIdOrName)'.",
                     file: #file,
                     function: #function,
                     line: #line)
        return nil
    }
    let appElement = AXUIElementCreateApplication(pid)
    axDebugLog("applicationElement: Created application element for PID \(pid) ('\(bundleIdOrName)').",
               file: #file,
               function: #function,
               line: #line)
    return Element(appElement)
}

// Convenience factory for application element from PID - already @MainActor
@MainActor
public func applicationElement(forProcessID pid: pid_t) -> Element? {
    guard pid > 0 else {
        axWarningLog("applicationElement: Invalid PID \(pid) provided.",
                     file: #file,
                     function: #function,
                     line: #line)
        return nil
    }
    let appElement = AXUIElementCreateApplication(pid)
    axDebugLog("applicationElement: Created application element for PID \(pid).",
               file: #file,
               function: #function,
               line: #line)
    return Element(appElement)
}

// Convenience factory for the system-wide element - already @MainActor
@MainActor
public func systemWideElement() -> Element {
    axDebugLog("Creating system-wide element.",
               file: #file,
               function: #function,
               line: #line)
    return Element(AXUIElementCreateSystemWide())
}
