import CoreGraphics
import Testing
@testable import AXorcist

@Suite("InputDriver cursor helpers")
struct InputDriverTests {
    @Test
    func `cachedLocation returns cached value when present`() {
        var cache: CGPoint? = CGPoint(x: 10, y: 20)
        let result = InputDriver.cachedLocation(using: &cache)
        #expect(result == CGPoint(x: 10, y: 20))
    }

    @Test
    func `cachedLocation populates cache when empty`() {
        var cache: CGPoint?
        let result = InputDriver.cachedLocation(using: &cache)
        #expect(cache == result)
    }

    @Test
    func `mouse button event kinds preserve all three buttons`() {
        #expect(MouseButton.left.eventKinds == MouseButtonEventKinds(
            button: .left,
            down: .leftMouseDown,
            dragged: .leftMouseDragged,
            up: .leftMouseUp))
        #expect(MouseButton.right.eventKinds == MouseButtonEventKinds(
            button: .right,
            down: .rightMouseDown,
            dragged: .rightMouseDragged,
            up: .rightMouseUp))
        #expect(MouseButton.middle.eventKinds == MouseButtonEventKinds(
            button: .center,
            down: .otherMouseDown,
            dragged: .otherMouseDragged,
            up: .otherMouseUp))
    }

    @Test
    @MainActor
    func `right drag prebuilds the complete matching event sequence`() throws {
        let events = try InputDriver.dragEvents(
            from: CGPoint(x: 10, y: 20),
            to: CGPoint(x: 30, y: 40),
            button: .right,
            steps: 2)

        #expect(events.down.type == .rightMouseDown)
        #expect(events.moves.map(\.type) == [.rightMouseDragged, .rightMouseDragged])
        #expect(events.up.type == .rightMouseUp)
    }

    @Test
    @MainActor
    func `drag allocation failure returns no partial sequence`() {
        var creationCount = 0
        do {
            _ = try InputDriver.dragEvents(
                from: CGPoint(x: 10, y: 20),
                to: CGPoint(x: 30, y: 40),
                button: .middle,
                steps: 3,
                makeEvent: { type, point, button in
                    creationCount += 1
                    guard creationCount < 3 else { return nil }
                    return CGEvent(
                        mouseEventSource: nil,
                        mouseType: type,
                        mouseCursorPosition: point,
                        mouseButton: button)
                })
            Issue.record("Expected drag event creation to fail")
        } catch UIAutomationError.failedToCreateEvent {
            // Expected: the builder returns no sequence for a caller to post.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(creationCount == 3)
    }

    @Test
    @MainActor
    func `press hold allocation failure returns before posting`() {
        var creationCount = 0
        do {
            _ = try InputDriver.pressHoldEvents(
                at: CGPoint(x: 10, y: 20),
                button: .middle,
                makeEvent: { type, point, button in
                    creationCount += 1
                    guard creationCount == 1 else { return nil }
                    return CGEvent(
                        mouseEventSource: nil,
                        mouseType: type,
                        mouseCursorPosition: point,
                        mouseButton: button)
                })
            Issue.record("Expected press-hold event creation to fail")
        } catch UIAutomationError.failedToCreateEvent {
            // Expected: mouse-down is never returned to the caller on partial allocation.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(creationCount == 2)
    }

    @Test
    @MainActor
    func `preallocated mouse events can be timestamped at delivery`() throws {
        let events = try InputDriver.pressHoldEvents(
            at: CGPoint(x: 10, y: 20),
            button: .left)

        InputDriver.refreshTimestamp(events.down, timestamp: 100)
        InputDriver.refreshTimestamp(events.up, timestamp: 200)

        #expect(events.down.timestamp == 100)
        #expect(events.up.timestamp == 200)
    }

    @Test
    @MainActor
    func `keyboardStroke maps printable ASCII to physical key events`() throws {
        let translateUSLayout: (CGKeyCode, CGEventFlags) -> Element.KeyboardTranslation? = { keyCode, flags in
            let text: String? = switch (keyCode, flags) {
            case (0, []): "a"
            case (0, .maskShift): "A"
            case (18, []): "1"
            case (18, .maskShift): "!"
            case (27, []): "-"
            case (27, .maskShift): "_"
            default: nil
            }
            return text.map { Element.KeyboardTranslation(text: $0, deadKeyState: 0) }
        }

        let lower = try #require(Element.keyboardStroke(for: "a", translatingWith: translateUSLayout))
        #expect(lower.keyCode == 0)
        #expect(!lower.flags.contains(.maskShift))

        let upper = try #require(Element.keyboardStroke(for: "A", translatingWith: translateUSLayout))
        #expect(upper.keyCode == 0)
        #expect(upper.flags.contains(.maskShift))

        let digit = try #require(Element.keyboardStroke(for: "1", translatingWith: translateUSLayout))
        #expect(digit.keyCode == 18)
        #expect(!digit.flags.contains(.maskShift))

        let symbol = try #require(Element.keyboardStroke(for: "!", translatingWith: translateUSLayout))
        #expect(symbol.keyCode == 18)
        #expect(symbol.flags.contains(.maskShift))

        let hyphen = try #require(Element.keyboardStroke(for: "-", translatingWith: translateUSLayout))
        #expect(hyphen.keyCode == 27)
        #expect(!hyphen.flags.contains(.maskShift))

        let underscore = try #require(Element.keyboardStroke(for: "_", translatingWith: translateUSLayout))
        #expect(underscore.keyCode == 27)
        #expect(underscore.flags.contains(.maskShift))
    }

    @Test
    @MainActor
    func `keyboardStroke follows the active keyboard layout`() throws {
        let translateQWERTZLayout: (CGKeyCode, CGEventFlags) -> Element.KeyboardTranslation? = { keyCode, flags in
            let text: String? = if keyCode == 6, flags.isEmpty {
                "y"
            } else if keyCode == 16, flags.isEmpty {
                "z"
            } else if keyCode == 37, flags == .maskAlternate {
                "@"
            } else {
                nil
            }
            return text.map { Element.KeyboardTranslation(text: $0, deadKeyState: 0) }
        }

        let z = try #require(Element.keyboardStroke(for: "z", translatingWith: translateQWERTZLayout))
        #expect(z.keyCode == 16)
        #expect(z.flags.isEmpty)

        let at = try #require(Element.keyboardStroke(for: "@", translatingWith: translateQWERTZLayout))
        #expect(at.keyCode == 37)
        #expect(at.flags == .maskAlternate)
    }

    @Test
    @MainActor
    func `keyboardStroke rejects dead key candidates`() throws {
        let translateDeadKeyLayout: (CGKeyCode, CGEventFlags) -> Element.KeyboardTranslation? = { keyCode, flags in
            guard flags.isEmpty else { return nil }
            if keyCode == 10 {
                return Element.KeyboardTranslation(text: "^", deadKeyState: 1)
            }
            if keyCode == 11 {
                return Element.KeyboardTranslation(text: "^", deadKeyState: 0)
            }
            return nil
        }

        let caret = try #require(Element.keyboardStroke(for: "^", translatingWith: translateDeadKeyLayout))
        #expect(caret.keyCode == 11)
    }

    @Test
    @MainActor
    func `keyboardStroke leaves non-ASCII for Unicode fallback`() {
        let translate: (CGKeyCode, CGEventFlags) -> Element.KeyboardTranslation? = { _, _ in
            Element.KeyboardTranslation(text: "é", deadKeyState: 0)
        }
        #expect(Element.keyboardStroke(for: "é", translatingWith: translate) == nil)
        #expect(Element.keyboardStroke(for: "🙂", translatingWith: translate) == nil)
    }

    @Test
    @MainActor
    func `hotkey events are fully built before posting`() throws {
        let descriptors = Element.hotkeyEventDescriptors(
            modifiers: [Element.HotkeyModifier(keyCode: 0x37, flag: .maskCommand)],
            mainKeyCode: 0)
        #expect(descriptors == [
            Element.KeyboardEventDescriptor(keyCode: 0x37, keyDown: true, flags: .maskCommand),
            Element.KeyboardEventDescriptor(keyCode: 0, keyDown: true, flags: .maskCommand),
            Element.KeyboardEventDescriptor(keyCode: 0, keyDown: false, flags: .maskCommand),
            Element.KeyboardEventDescriptor(keyCode: 0x37, keyDown: false, flags: []),
        ])

        var creationCount = 0
        do {
            _ = try Element.keyboardEvents(for: descriptors) { descriptor in
                creationCount += 1
                guard creationCount < 3 else { return nil }
                return CGEvent(
                    keyboardEventSource: nil,
                    virtualKey: descriptor.keyCode,
                    keyDown: descriptor.keyDown)
            }
            Issue.record("Expected event creation to fail")
        } catch UIAutomationError.failedToCreateEvent {
            // Expected: no caller can post this incomplete event array.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(creationCount == 3)
    }
}
