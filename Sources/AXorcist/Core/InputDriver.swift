import AppKit
import CoreGraphics
import Dispatch
import Foundation

/// Lightweight, allocation-conscious helpers for synthesizing user input.
///
/// These intentionally stay thin: no logging, no implicit delays beyond what
/// the underlying AX/UI toolkits already impose. Callers (e.g. Peekaboo) can
/// layer heuristics or visualization on top without paying a baseline tax.
public enum InputDriver {
    typealias MouseEventFactory = @MainActor (CGEventType, CGPoint, CGMouseButton) -> CGEvent?

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
        if let cached = cache {
            return cached
        }
        let loc = self.currentLocation()
        cache = loc
        return loc
    }

    /// Press and hold at a point for a duration (simulates force click fallback).
    @MainActor
    public static func pressHold(at point: CGPoint, button: MouseButton = .left, duration: TimeInterval) throws {
        let events = try self.pressHoldEvents(at: point, button: button)
        self.refreshTimestamp(events.down)
        events.down.post(tap: .cghidEventTap)

        if duration > 0 {
            Thread.sleep(forTimeInterval: duration)
        }

        self.refreshTimestamp(events.up)
        events.up.post(tap: .cghidEventTap)
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
        let events = try self.dragEvents(from: start, to: end, button: button, steps: steps)
        self.refreshTimestamp(events.down)
        events.down.post(tap: .cghidEventTap)

        for move in events.moves {
            self.refreshTimestamp(move)
            move.post(tap: .cghidEventTap)
            if interStepDelay > 0 {
                Thread.sleep(forTimeInterval: interStepDelay)
            }
        }

        self.refreshTimestamp(events.up)
        events.up.post(tap: .cghidEventTap)
    }

    @MainActor
    static func pressHoldEvents(
        at point: CGPoint,
        button: MouseButton,
        makeEvent: MouseEventFactory = InputDriver.makeMouseEvent) throws -> (down: CGEvent, up: CGEvent)
    {
        let eventKinds = button.eventKinds
        guard let down = makeEvent(eventKinds.down, point, eventKinds.button),
              let up = makeEvent(eventKinds.up, point, eventKinds.button)
        else {
            throw UIAutomationError.failedToCreateEvent
        }
        down.setDoubleValueField(.mouseEventPressure, value: 2.0)
        return (down, up)
    }

    @MainActor
    static func dragEvents(
        from start: CGPoint,
        to end: CGPoint,
        button: MouseButton,
        steps requestedSteps: Int,
        makeEvent: MouseEventFactory = InputDriver.makeMouseEvent) throws -> (
        down: CGEvent,
        moves: [CGEvent],
        up: CGEvent)
    {
        let steps = max(1, requestedSteps)
        let eventKinds = button.eventKinds
        guard let down = makeEvent(eventKinds.down, start, eventKinds.button) else {
            throw UIAutomationError.failedToCreateEvent
        }

        var moves: [CGEvent] = []
        moves.reserveCapacity(steps)
        for index in 1...steps {
            let progress = CGFloat(index) / CGFloat(steps)
            let position = CGPoint(
                x: start.x + (end.x - start.x) * progress,
                y: start.y + (end.y - start.y) * progress)
            guard let move = makeEvent(eventKinds.dragged, position, eventKinds.button) else {
                throw UIAutomationError.failedToCreateEvent
            }
            moves.append(move)
        }

        guard let up = makeEvent(eventKinds.up, end, eventKinds.button) else {
            throw UIAutomationError.failedToCreateEvent
        }
        return (down, moves, up)
    }

    @MainActor
    static func refreshTimestamp(
        _ event: CGEvent,
        timestamp: CGEventTimestamp = DispatchTime.now().uptimeNanoseconds)
    {
        event.timestamp = timestamp
    }

    @MainActor
    private static func makeMouseEvent(
        type: CGEventType,
        point: CGPoint,
        button: CGMouseButton) -> CGEvent?
    {
        CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: button)
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
