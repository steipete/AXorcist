import CoreGraphics
import Testing
@testable import AXorcist

@Suite("Hotkey digit keys")
struct SpecialKeyDigitTests {
    @Test("SpecialKey parses digit keys 0-9")
    func digitKeysParse() {
        let cases: [(String, CGKeyCode)] = [
            ("0", 29),
            ("1", 18),
            ("2", 19),
            ("3", 20),
            ("4", 21),
            ("5", 23),
            ("6", 22),
            ("7", 26),
            ("8", 28),
            ("9", 25),
        ]

        for (rawValue, expectedCode) in cases {
            let key = SpecialKey(rawValue: rawValue)
            #expect(key != nil)
            #expect(key?.keyCode == expectedCode)
        }
    }
}

