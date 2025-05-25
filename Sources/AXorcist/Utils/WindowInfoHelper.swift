//
//  WindowInfoHelper.swift
//  AXorcist
//
//  Helper utilities for getting window information using CGWindowListCopyWindowInfo
//

import ApplicationServices
import CoreGraphics
import Foundation

public struct WindowInfoHelper {
    /// Get window info list with specified options
    public static func getWindowInfoList(
        option: CGWindowListOption,
        relativeToWindow windowID: CGWindowID = kCGNullWindowID
    ) -> [[String: Any]]? {
        guard let info = CGWindowListCopyWindowInfo(option, windowID) as? [[String: Any]] else {
            return nil
        }
        return info
    }

    /// Get all visible windows on screen (excluding desktop elements)
    public static func getVisibleWindows() -> [[String: Any]]? {
        let options = CGWindowListOption.optionOnScreenOnly.union(.excludeDesktopElements)
        return getWindowInfoList(option: options)
    }

    /// Get all windows on screen (including desktop elements)
    public static func getAllWindowsOnScreen() -> [[String: Any]]? {
        return getWindowInfoList(option: .optionOnScreenOnly)
    }

    /// Get window info for a specific window number
    public static func getWindowInfo(
        windowNumber: Int,
        option: CGWindowListOption = .optionOnScreenOnly
    ) -> [String: Any]? {
        guard let windowInfos = getWindowInfoList(option: option) else {
            return nil
        }

        return windowInfos.first { dict in
            if let winNum = dict[kCGWindowNumber as String] as? Int {
                return winNum == windowNumber
            }
            return false
        }
    }

    /// Get all windows for a specific process ID
    public static func getWindows(for pid: pid_t) -> [[String: Any]]? {
        guard let allWindows = getVisibleWindows() else {
            return nil
        }

        return allWindows.filter { dict in
            if let ownerPID = dict[kCGWindowOwnerPID as String] as? Int {
                return ownerPID == Int(pid)
            }
            return false
        }
    }

    /// Get the window ID from an AXUIElement (if available via private API)
    /// Note: This uses the private API _AXUIElementGetWindow if available
    @MainActor
    public static func getWindowID(from element: Element) -> CGWindowID? {
        // Check if this is actually a window element
        guard element.role() == kAXWindowRole else {
            axDebugLog("Element is not a window, cannot get window ID")
            return nil
        }

        // Try to match by position and size with CGWindowList
        guard let position = element.position(),
              let size = element.size(),
              let pid = element.pid() else {
            return nil
        }

        // Get all windows for this PID
        guard let windows = getWindows(for: pid) else {
            return nil
        }

        // Try to find matching window by bounds
        for window in windows {
            if let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
               let x = bounds["X"],
               let y = bounds["Y"],
               let width = bounds["Width"],
               let height = bounds["Height"] {

                // Check if bounds match (with small tolerance for floating point comparison)
                let tolerance: CGFloat = 1.0
                if abs(x - position.x) < tolerance &&
                    abs(y - position.y) < tolerance &&
                    abs(width - size.width) < tolerance &&
                    abs(height - size.height) < tolerance {

                    if let windowID = window[kCGWindowNumber as String] as? Int {
                        return CGWindowID(windowID)
                    }
                }
            }
        }

        return nil
    }

    /// Get the bounds of a window
    public static func getWindowBounds(windowID: CGWindowID) -> CGRect? {
        guard let info = getWindowInfo(windowNumber: Int(windowID)) else {
            return nil
        }

        guard let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
              let x = bounds["X"],
              let y = bounds["Y"],
              let width = bounds["Width"],
              let height = bounds["Height"] else {
            return nil
        }

        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Get the owning application's PID for a window
    public static func getOwnerPID(windowID: CGWindowID) -> pid_t? {
        guard let info = getWindowInfo(windowNumber: Int(windowID)) else {
            return nil
        }

        guard let pid = info[kCGWindowOwnerPID as String] as? Int else {
            return nil
        }

        return pid_t(pid)
    }

    /// Get the window's name/title
    public static func getWindowName(windowID: CGWindowID) -> String? {
        guard let info = getWindowInfo(windowNumber: Int(windowID)) else {
            return nil
        }

        return info[kCGWindowName as String] as? String
    }

    /// Check if a window is on screen
    public static func isWindowOnScreen(windowID: CGWindowID) -> Bool {
        return getWindowInfo(windowNumber: Int(windowID), option: .optionOnScreenOnly) != nil
    }
}
