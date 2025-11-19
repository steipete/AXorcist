import AppKit
import CoreGraphics
import Foundation

/// Lightweight, allocation-conscious helpers for synthesizing user input.
///
/// These intentionally stay thin: no logging, no implicit delays beyond what
/// the underlying AX/UI toolkits already impose. Callers (e.g. Peekaboo) can
/// layer heuristics or visualization on top without paying a baseline tax.
public enum InputDriver {
    // MARK: - Mouse

    /// Click at a screen point.
    @MainActor
    public static func click(
        at point: CGPoint,
        button: MouseButton = .left,
        count: Int = 1) throws
    {
        try Element.clickAt(point, button: button, clickCount: count)
    }

    /// Move mouse to a point (no click)
    @MainActor
    public static func move(to point: CGPoint) throws {
        guard let moveEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: point,
            mouseButton: .left)
        else { throw UIAutomationError.failedToCreateEvent }
        moveEvent.post(tap: .cghidEventTap)
    }

    /// Current mouse location (if available).
    public static func currentLocation() -> CGPoint? {
        CGEvent(source: nil)?.location
    }

    /// Cached current location provider to avoid repeated CGEvent creation in tight loops.
    public static func cachedLocation(using cache: inout CGPoint?) -> CGPoint? {
        if let cached = cache { return cached }
        let loc = self.currentLocation()
        cache = loc
        return loc
    }

    /// Press and hold at a point for a duration (simulates force click fallback).
    @MainActor
    public static func pressHold(at point: CGPoint, button: MouseButton = .left, duration: TimeInterval) throws {
        let buttonType: CGMouseButton = (button == .left ? .left : .right)
        let downType: CGEventType = (button == .left ? .leftMouseDown : .rightMouseDown)
        let upType: CGEventType = (button == .left ? .leftMouseUp : .rightMouseUp)

        guard let down = CGEvent(
            mouseEventSource: nil,
            mouseType: downType,
            mouseCursorPosition: point,
            mouseButton: buttonType)
        else { throw UIAutomationError.failedToCreateEvent }
        down.setDoubleValueField(.mouseEventPressure, value: 2.0)
        down.post(tap: .cghidEventTap)

        if duration > 0 {
            Thread.sleep(forTimeInterval: duration)
        }

        guard let up = CGEvent(
            mouseEventSource: nil,
            mouseType: upType,
            mouseCursorPosition: point,
            mouseButton: buttonType)
        else { throw UIAutomationError.failedToCreateEvent }
        up.post(tap: .cghidEventTap)
    }

    /// Drag from → to using the given button.
    @MainActor
    public static func drag(
        from start: CGPoint,
        to end: CGPoint,
        button: MouseButton = .left,
        steps: Int = 20,
        interStepDelay: TimeInterval = 0.0) throws
    {
        let steps = max(1, steps)

        let buttonType: CGMouseButton = (button == .left ? .left : .right)
        let downType: CGEventType = (button == .left ? .leftMouseDown : .rightMouseDown)
        let dragType: CGEventType = .leftMouseDragged
        let upType: CGEventType = (button == .left ? .leftMouseUp : .rightMouseUp)

        guard let down = CGEvent(
            mouseEventSource: nil,
            mouseType: downType,
            mouseCursorPosition: start,
            mouseButton: buttonType)
        else { throw UIAutomationError.failedToCreateEvent }
        down.post(tap: .cghidEventTap)

        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let pos = CGPoint(
                x: start.x + (end.x - start.x) * t,
                y: start.y + (end.y - start.y) * t)
            guard let move = CGEvent(
                mouseEventSource: nil,
                mouseType: dragType,
                mouseCursorPosition: pos,
                mouseButton: buttonType)
            else { continue }
            move.post(tap: .cghidEventTap)
            if interStepDelay > 0 { Thread.sleep(forTimeInterval: interStepDelay) }
        }

        guard let up = CGEvent(
            mouseEventSource: nil,
            mouseType: upType,
            mouseCursorPosition: end,
            mouseButton: buttonType)
        else { throw UIAutomationError.failedToCreateEvent }
        up.post(tap: .cghidEventTap)
    }

    /// Scroll by deltas (line-based). Positive `deltaY` scrolls up.
    @MainActor
    public static func scroll(
        deltaX: Double = 0,
        deltaY: Double,
        at point: CGPoint? = nil) throws
    {
        let pixelsPerLine: Double = 10
        let scrollEvent = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 2,
            wheel1: Int32(deltaY / pixelsPerLine),
            wheel2: Int32(deltaX / pixelsPerLine),
            wheel3: 0)

        guard let event = scrollEvent else { throw UIAutomationError.failedToCreateEvent }
        if let point {
            event.location = point
        }
        event.post(tap: .cghidEventTap)
    }

    // MARK: - Keyboard

    /// Type a string at the current focus.
    @MainActor
    public static func type(_ text: String, delayPerCharacter: TimeInterval = 0.0) throws {
        try Element.typeText(text, delay: delayPerCharacter)
    }

    /// Tap a special key (e.g. return, tab) with optional modifiers.
    @MainActor
    public static func tapKey(_ key: SpecialKey, modifiers: CGEventFlags = []) throws {
        try Element.typeKey(key, modifiers: modifiers)
    }

    /// Perform a hotkey chord (e.g. ["cmd","shift","4"]).
    @MainActor
    public static func hotkey(keys: [String], holdDuration: TimeInterval = 0.1) throws {
        try Element.performHotkey(keys: keys, holdDuration: holdDuration)
    }
}
