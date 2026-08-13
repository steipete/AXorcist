import AppKit
import ApplicationServices
import Carbon.HIToolbox

// MARK: - Mouse Button Types

public enum MouseButton: String, Sendable {
    case left
    case right
    case middle
}

struct MouseButtonEventKinds: Equatable {
    let button: CGMouseButton
    let down: CGEventType
    let dragged: CGEventType
    let up: CGEventType
}

extension MouseButton {
    var eventKinds: MouseButtonEventKinds {
        switch self {
        case .left:
            MouseButtonEventKinds(
                button: .left,
                down: .leftMouseDown,
                dragged: .leftMouseDragged,
                up: .leftMouseUp)
        case .right:
            MouseButtonEventKinds(
                button: .right,
                down: .rightMouseDown,
                dragged: .rightMouseDragged,
                up: .rightMouseUp)
        case .middle:
            MouseButtonEventKinds(
                button: .center,
                down: .otherMouseDown,
                dragged: .otherMouseDragged,
                up: .otherMouseUp)
        }
    }
}

// MARK: - Click Operations

extension Element {
    /// Click on this element
    @MainActor public func click(button: MouseButton = .left, clickCount: Int = 1) throws {
        // Ensure element is actionable
        guard isEnabled() ?? true else {
            throw UIAutomationError.elementNotEnabled
        }

        // Get element center
        guard let frame = frame() else {
            throw UIAutomationError.missingFrame
        }

        let center = CGPoint(x: frame.midX, y: frame.midY)

        // Perform click at center
        try Element.clickAt(center, button: button, clickCount: clickCount)
    }

    /// Click at a specific point on screen
    @MainActor public static func clickAt(_ point: CGPoint, button: MouseButton = .left, clickCount: Int = 1) throws {
        let clickPairs = try self.buildClickEventPairs(at: point, button: button, clickCount: clickCount)

        for (index, pair) in clickPairs.enumerated() {
            pair.down.post(tap: .cghidEventTap)

            // Small delay between down and up
            Thread.sleep(forTimeInterval: 0.01)

            pair.up.post(tap: .cghidEventTap)

            // Small delay between successive clicks (stay within the system double-click interval)
            if index < clickPairs.count - 1 {
                Thread.sleep(forTimeInterval: 0.03)
            }
        }
    }

    @MainActor
    static func buildClickEventPairs(
        at point: CGPoint,
        button: MouseButton,
        clickCount: Int) throws -> [(down: CGEvent, up: CGEvent)]
    {
        let clampedCount = max(1, clickCount)

        let eventKinds = button.eventKinds

        var pairs: [(down: CGEvent, up: CGEvent)] = []
        pairs.reserveCapacity(clampedCount)

        for clickIndex in 1...clampedCount {
            guard let mouseDown = CGEvent(
                mouseEventSource: nil,
                mouseType: eventKinds.down,
                mouseCursorPosition: point,
                mouseButton: eventKinds.button)
            else {
                throw UIAutomationError.failedToCreateEvent
            }

            guard let mouseUp = CGEvent(
                mouseEventSource: nil,
                mouseType: eventKinds.up,
                mouseCursorPosition: point,
                mouseButton: eventKinds.button)
            else {
                throw UIAutomationError.failedToCreateEvent
            }

            // For a double click, the system expects a sequence of click states:
            // (1) down/up with clickState=1, then (2) down/up with clickState=2.
            let clickState = Int64(clickIndex)
            mouseDown.setIntegerValueField(.mouseEventClickState, value: clickState)
            mouseUp.setIntegerValueField(.mouseEventClickState, value: clickState)

            pairs.append((down: mouseDown, up: mouseUp))
        }

        return pairs
    }

    /// Wait for this element to become actionable
    @MainActor public func waitUntilActionable(
        timeout: TimeInterval = 5.0,
        pollInterval: TimeInterval = 0.1) async throws -> Element
    {
        let startTime = Date()

        while Date().timeIntervalSince(startTime) < timeout {
            // Check if element is actionable
            if self.isActionable() {
                return self
            }

            // Wait before next check
            try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }

        throw UIAutomationError.elementNotActionable(timeout: timeout)
    }

    /// Check if element is actionable (enabled, visible, on screen)
    @MainActor public func isActionable() -> Bool {
        // Must be enabled
        guard isEnabled() ?? true else { return false }

        // Must have a frame
        guard let frame = frame() else { return false }

        // Must be on screen
        guard frame.width > 0, frame.height > 0 else { return false }

        // Check if on any screen
        return NSScreen.screens.contains { screen in
            screen.frame.intersects(frame)
        }
    }
}

// MARK: - Keyboard Operations

extension Element {
    /// Type text into this element
    @MainActor public func typeText(_ text: String, delay: TimeInterval = 0.005, clearFirst: Bool = false) throws {
        try self.typeText(
            text,
            delay: delay,
            clearFirst: clearFirst,
            ensureFocus: {
                self.attribute(Attribute<Bool>.focused) == true ||
                    self.setValue(true, forAttribute: Attribute<Bool>.focused.rawValue)
            },
            eventDispatcher: { text, delay, clearFirst in
                if clearFirst {
                    try self.clearField()
                }
                try Element.typeText(text, delay: delay)
            })
    }

    @MainActor
    func typeText(
        _ text: String,
        delay: TimeInterval,
        clearFirst: Bool,
        ensureFocus: () -> Bool,
        eventDispatcher: (String, TimeInterval, Bool) throws -> Void) throws
    {
        guard ensureFocus() else {
            throw ElementTypingError.focusFailed
        }
        try eventDispatcher(text, delay, clearFirst)
    }

    /// Clear the text field
    @MainActor public func clearField() throws {
        // Select all with Cmd+A
        try Element.performHotkey(keys: ["cmd", "a"])
        Thread.sleep(forTimeInterval: 0.05)

        // Delete
        try Element.typeKey(.delete)
    }

    /// Type text at current focus
    @MainActor public static func typeText(_ text: String, delay: TimeInterval = 0.005) throws {
        for character in text {
            if character == "\n" {
                try self.typeKey(.return)
            } else if character == "\t" {
                try self.typeKey(.tab)
            } else {
                try self.typeCharacter(character)
            }

            Thread.sleep(forTimeInterval: delay > 0 ? delay : 0.001)
        }
    }

    /// Type a single character
    @MainActor public static func typeCharacter(_ character: Character) throws {
        // Physical key events survive VM/headless launch paths that can silently drop Unicode-only events.
        // Resolve them through the active layout so the resulting text remains layout-independent.
        if let stroke = self.keyboardStroke(for: character) {
            try self.postKeyboardStroke(stroke)
            return
        }

        try self.postUnicodeCharacter(character)
    }

    static func keyboardStroke(for character: Character) -> (keyCode: CGKeyCode, flags: CGEventFlags)? {
        guard
            let inputSource = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
            let rawLayoutData = TISGetInputSourceProperty(inputSource, kTISPropertyUnicodeKeyLayoutData)
        else {
            return nil
        }

        let layoutData = Unmanaged<CFData>.fromOpaque(rawLayoutData).takeUnretainedValue()
        guard let layoutBytes = CFDataGetBytePtr(layoutData) else { return nil }
        let layout = UnsafeRawPointer(layoutBytes).assumingMemoryBound(to: UCKeyboardLayout.self)

        return self.keyboardStroke(for: character) { keyCode, flags in
            self.translatedString(for: keyCode, flags: flags, layout: layout)
        }
    }

    static func keyboardStroke(
        for character: Character,
        translatingWith translate: (CGKeyCode, CGEventFlags) -> KeyboardTranslation?)
        -> (keyCode: CGKeyCode, flags: CGEventFlags)?
    {
        let expected = String(character)
        guard expected.unicodeScalars.count == 1,
              let scalar = expected.unicodeScalars.first,
              scalar.isASCII,
              (0x20...0x7E).contains(scalar.value)
        else {
            return nil
        }

        let modifierOptions: [CGEventFlags] = [
            [],
            .maskShift,
            .maskAlternate,
            .maskShift.union(.maskAlternate),
        ]

        for flags in modifierOptions {
            for keyCode in CGKeyCode(0)...CGKeyCode(127) {
                guard let translation = translate(keyCode, flags),
                      translation.deadKeyState == 0,
                      translation.text == expected
                else {
                    continue
                }
                return (keyCode, flags)
            }
        }

        return nil
    }

    private static func translatedString(
        for keyCode: CGKeyCode,
        flags: CGEventFlags,
        layout: UnsafePointer<UCKeyboardLayout>) -> KeyboardTranslation?
    {
        var carbonModifiers: UInt32 = 0
        if flags.contains(.maskShift) {
            carbonModifiers |= UInt32(shiftKey)
        }
        if flags.contains(.maskAlternate) {
            carbonModifiers |= UInt32(optionKey)
        }

        var deadKeyState: UInt32 = 0
        var actualLength = 0
        var codeUnits = [UniChar](repeating: 0, count: 8)
        let status = UCKeyTranslate(
            layout,
            keyCode,
            UInt16(kUCKeyActionDown),
            (carbonModifiers >> 8) & 0xFF,
            UInt32(LMGetKbdType()),
            OptionBits(0),
            &deadKeyState,
            codeUnits.count,
            &actualLength,
            &codeUnits)

        guard status == noErr else { return nil }
        return KeyboardTranslation(
            text: String(utf16CodeUnits: codeUnits, count: actualLength),
            deadKeyState: deadKeyState)
    }

    struct KeyboardTranslation {
        let text: String
        let deadKeyState: UInt32
    }

    private static func postKeyboardStroke(_ stroke: (keyCode: CGKeyCode, flags: CGEventFlags)) throws {
        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: stroke.keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: stroke.keyCode, keyDown: false)
        else {
            throw UIAutomationError.failedToCreateEvent
        }

        keyDown.flags = stroke.flags
        keyUp.flags = stroke.flags
        keyDown.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.001)
        keyUp.post(tap: .cghidEventTap)
    }

    private static func postUnicodeCharacter(_ character: Character) throws {
        let string = String(character)

        // Create keyboard event
        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true) else {
            throw UIAutomationError.failedToCreateEvent
        }

        // Set the character
        let chars = Array(string.utf16)
        chars.withUnsafeBufferPointer { buffer in
            keyDown.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: buffer.baseAddress!)
        }

        // Create key up event
        guard let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else {
            throw UIAutomationError.failedToCreateEvent
        }
        chars.withUnsafeBufferPointer { buffer in
            keyUp.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: buffer.baseAddress!)
        }

        // Post events
        keyDown.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.001)
        keyUp.post(tap: .cghidEventTap)
    }

    /// Type a special key
    @MainActor public static func typeKey(_ key: SpecialKey, modifiers: CGEventFlags = []) throws {
        guard let keyCode = key.keyCode else {
            throw UIAutomationError.unsupportedKey(key.rawValue)
        }

        // Create key down event
        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true) else {
            throw UIAutomationError.failedToCreateEvent
        }
        keyDown.flags = modifiers

        // Create key up event
        guard let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
            throw UIAutomationError.failedToCreateEvent
        }
        keyUp.flags = modifiers

        // Post events
        keyDown.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.001)
        keyUp.post(tap: .cghidEventTap)
    }

    /// Perform a hotkey combination
    @MainActor public static func performHotkey(keys: [String], holdDuration: TimeInterval = 0.1) throws {
        var modifiers: [HotkeyModifier] = []
        var mainKey: SpecialKey?

        // Parse keys
        for key in keys {
            switch key.lowercased() {
            case "cmd", "command":
                modifiers.append(HotkeyModifier(keyCode: 0x37, flag: .maskCommand))
            case "shift":
                modifiers.append(HotkeyModifier(keyCode: 0x38, flag: .maskShift))
            case "option", "opt", "alt":
                modifiers.append(HotkeyModifier(keyCode: 0x3A, flag: .maskAlternate))
            case "ctrl", "control":
                modifiers.append(HotkeyModifier(keyCode: 0x3B, flag: .maskControl))
            case "fn", "function":
                modifiers.append(HotkeyModifier(keyCode: nil, flag: .maskSecondaryFn))
            default:
                // Try to parse as special key
                if let special = SpecialKey(rawValue: key.lowercased()) {
                    mainKey = special
                } else if key.count == 1 {
                    // Single character key
                    let char = key.lowercased().first!
                    mainKey = SpecialKey(character: char)
                }
            }
        }

        // Must have a main key
        guard let key = mainKey else {
            throw UIAutomationError.invalidHotkey(keys.joined(separator: "+"))
        }

        guard let mainKeyCode = key.keyCode else {
            throw UIAutomationError.unsupportedKey(key.rawValue)
        }

        let descriptors = self.hotkeyEventDescriptors(modifiers: modifiers, mainKeyCode: mainKeyCode)
        // Build the complete sequence before posting anything. Event creation can fail; posting cannot.
        let events = try self.keyboardEvents(for: descriptors) { descriptor in
            CGEvent(
                keyboardEventSource: nil,
                virtualKey: descriptor.keyCode,
                keyDown: descriptor.keyDown)
        }

        for (descriptor, event) in zip(descriptors, events) {
            event.post(tap: .cghidEventTap)
            if descriptor.keyCode == mainKeyCode, descriptor.keyDown, holdDuration > 0 {
                Thread.sleep(forTimeInterval: holdDuration)
            }
        }
    }

    struct HotkeyModifier {
        let keyCode: CGKeyCode?
        let flag: CGEventFlags
    }

    struct KeyboardEventDescriptor: Equatable {
        let keyCode: CGKeyCode
        let keyDown: Bool
        let flags: CGEventFlags
    }

    static func hotkeyEventDescriptors(
        modifiers: [HotkeyModifier],
        mainKeyCode: CGKeyCode) -> [KeyboardEventDescriptor]
    {
        var descriptors: [KeyboardEventDescriptor] = []
        var activeFlags: CGEventFlags = []

        for modifier in modifiers {
            activeFlags.insert(modifier.flag)
            if let keyCode = modifier.keyCode {
                descriptors.append(KeyboardEventDescriptor(keyCode: keyCode, keyDown: true, flags: activeFlags))
            }
        }

        descriptors.append(KeyboardEventDescriptor(keyCode: mainKeyCode, keyDown: true, flags: activeFlags))
        descriptors.append(KeyboardEventDescriptor(keyCode: mainKeyCode, keyDown: false, flags: activeFlags))

        for modifier in modifiers.reversed() {
            activeFlags.remove(modifier.flag)
            if let keyCode = modifier.keyCode {
                descriptors.append(KeyboardEventDescriptor(keyCode: keyCode, keyDown: false, flags: activeFlags))
            }
        }

        return descriptors
    }

    static func keyboardEvents(
        for descriptors: [KeyboardEventDescriptor],
        factory: (KeyboardEventDescriptor) -> CGEvent?) throws -> [CGEvent]
    {
        try descriptors.map { descriptor in
            guard let event = factory(descriptor) else {
                throw UIAutomationError.failedToCreateEvent
            }
            event.flags = descriptor.flags
            return event
        }
    }
}

// MARK: - Special Keys

// swiftlint:disable identifier_name
public enum SpecialKey: String {
    case escape
    case tab
    case space
    case delete
    case forwardDelete = "forwarddelete"
    case `return`
    case enter
    case up
    case down
    case left
    case right
    case pageUp = "pageup"
    case pageDown = "pagedown"
    case home
    case end
    case f1
    case f2
    case f3
    case f4
    case f5
    case f6
    case f7
    case f8
    case f9
    case f10
    case f11
    case f12

    // Single character keys
    case a
    case b
    case c
    case d
    case e
    case f
    case g
    case h
    case i
    case j
    case k
    case l
    case m
    case n
    case o
    case p
    case q
    case r
    case s
    case t
    case u
    case v
    case w
    case x
    case y
    case z

    // Digit keys
    case zero = "0"
    case one = "1"
    case two = "2"
    case three = "3"
    case four = "4"
    case five = "5"
    case six = "6"
    case seven = "7"
    case eight = "8"
    case nine = "9"

    init?(character: Character) {
        if let special = SpecialKey(rawValue: String(character).lowercased()) {
            self = special
        } else {
            return nil
        }
    }

    var keyCode: CGKeyCode? {
        switch self {
        case .escape: 53
        case .tab: 48
        case .space: 49
        case .delete: 51
        case .forwardDelete: 117
        case .return, .enter: 36
        case .up: 126
        case .down: 125
        case .left: 123
        case .right: 124
        case .pageUp: 116
        case .pageDown: 121
        case .home: 115
        case .end: 119
        case .f1: 122
        case .f2: 120
        case .f3: 99
        case .f4: 118
        case .f5: 96
        case .f6: 97
        case .f7: 98
        case .f8: 100
        case .f9: 101
        case .f10: 109
        case .f11: 103
        case .f12: 111
        case .a: 0
        case .b: 11
        case .c: 8
        case .d: 2
        case .e: 14
        case .f: 3
        case .g: 5
        case .h: 4
        case .i: 34
        case .j: 38
        case .k: 40
        case .l: 37
        case .m: 46
        case .n: 45
        case .o: 31
        case .p: 35
        case .q: 12
        case .r: 15
        case .s: 1
        case .t: 17
        case .u: 32
        case .v: 9
        case .w: 13
        case .x: 7
        case .y: 16
        case .z: 6
        case .zero: 29
        case .one: 18
        case .two: 19
        case .three: 20
        case .four: 21
        case .five: 23
        case .six: 22
        case .seven: 26
        case .eight: 28
        case .nine: 25
        }
    }
}

// swiftlint:enable identifier_name

// MARK: - Scroll Operations

// swiftlint:disable identifier_name
public enum ScrollDirection: String, Sendable {
    case up
    case down
    case left
    case right
}

// swiftlint:enable identifier_name

extension Element {
    /// Scroll this element in a specific direction
    @MainActor public func scroll(direction: ScrollDirection, amount: Int = 3, smooth: Bool = false) throws {
        // Get element bounds for scroll location
        guard let frame = frame() else {
            throw UIAutomationError.missingFrame
        }

        let center = CGPoint(x: frame.midX, y: frame.midY)

        // Perform scroll at element center
        try Element.scrollAt(center, direction: direction, amount: amount, smooth: smooth)
    }

    /// Scroll at a specific point
    @MainActor public static func scrollAt(
        _ point: CGPoint,
        direction: ScrollDirection,
        amount: Int = 3,
        smooth: Bool = false) throws
    {
        let scrollAmount = smooth ? 1 : amount
        let iterations = smooth ? amount : 1
        let delay = smooth ? 0.01 : 0.05

        for _ in 0..<iterations {
            // Create scroll event
            guard let scrollEvent = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 2,
                wheel1: direction == .up || direction == .down ? Int32(scrollAmount) : 0,
                wheel2: direction == .left || direction == .right ? Int32(scrollAmount) : 0,
                wheel3: 0)
            else {
                throw UIAutomationError.failedToCreateEvent
            }

            // Set scroll direction
            switch direction {
            case .up:
                scrollEvent.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: Int64(scrollAmount))
            case .down:
                scrollEvent.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: -Int64(scrollAmount))
            case .left:
                scrollEvent.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: Int64(scrollAmount))
            case .right:
                scrollEvent.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: -Int64(scrollAmount))
            }

            // Set location
            scrollEvent.location = point

            // Post event
            scrollEvent.post(tap: .cghidEventTap)

            // Delay between scrolls
            if iterations > 1 {
                Thread.sleep(forTimeInterval: delay)
            }
        }
    }
}

// MARK: - Element Finding

extension Element {
    /// Find element at a specific screen location
    @MainActor public static func elementAt(_ point: CGPoint, role: String? = nil) -> Element? {
        // Get element at point
        let element = Element.elementAtPoint(point)

        // If role specified, check if matches
        if let role, let found = element {
            if found.role() != role {
                // Try to find parent with matching role
                var current: Element? = found
                while let parent = current?.parent() {
                    if parent.role() == role {
                        return parent
                    }
                    current = parent
                }
                return nil
            }
        }

        return element
    }

    /// Find elements matching specific criteria
    @MainActor public func findElements(
        role: String? = nil,
        title: String? = nil,
        label: String? = nil,
        value: String? = nil,
        identifier: String? = nil,
        maxDepth: Int = 10) -> [Element]
    {
        var results: [Element] = []

        // Check self
        if self.matchesCriteria(role: role, title: title, label: label, value: value, identifier: identifier) {
            results.append(self)
        }

        // Check children recursively
        if maxDepth > 0 {
            if let children = children() {
                for child in children {
                    results.append(contentsOf: child.findElements(
                        role: role,
                        title: title,
                        label: label,
                        value: value,
                        identifier: identifier,
                        maxDepth: maxDepth - 1))
                }
            }
        }

        return results
    }

    /// Check if element matches criteria
    @MainActor private func matchesCriteria(
        role: String? = nil,
        title: String? = nil,
        label: String? = nil,
        value: String? = nil,
        identifier: String? = nil) -> Bool
    {
        // Check role
        if let role, self.role() != role {
            return false
        }

        // Check title
        if let title, self.title() != title {
            return false
        }

        // Check label (using description as label)
        if let label, self.descriptionText() != label {
            return false
        }

        // Check value
        if let value, self.value() as? String != value {
            return false
        }

        // Check identifier
        if let identifier, self.identifier() != identifier {
            return false
        }

        return true
    }
}

// MARK: - UI Automation Errors

public enum UIAutomationError: Error, LocalizedError {
    case failedToCreateEvent
    case elementNotEnabled
    case elementNotActionable(timeout: TimeInterval)
    case unsupportedKey(String)
    case invalidHotkey(String)
    case missingFrame

    public var errorDescription: String? {
        switch self {
        case .failedToCreateEvent:
            "Failed to create system event"
        case .elementNotEnabled:
            "Element is not enabled"
        case let .elementNotActionable(timeout):
            "Element did not become actionable within \(timeout) seconds"
        case let .unsupportedKey(key):
            "Unsupported key: \(key)"
        case let .invalidHotkey(keys):
            "Invalid hotkey combination: \(keys)"
        case .missingFrame:
            "Element has no frame attribute"
        }
    }
}

enum ElementTypingError: Error, LocalizedError {
    case focusFailed

    var errorDescription: String? {
        "Failed to focus element before typing"
    }
}
