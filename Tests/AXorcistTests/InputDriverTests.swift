import CoreGraphics
import Testing
@testable import AXorcist

@Suite("InputDriver cursor helpers")
struct InputDriverTests {
    @Test("cachedLocation returns cached value when present")
    func cachedLocationUsesCache() {
        var cache: CGPoint? = CGPoint(x: 10, y: 20)
        let result = InputDriver.cachedLocation(using: &cache)
        #expect(result == CGPoint(x: 10, y: 20))
    }

    @Test("cachedLocation populates cache when empty")
    func cachedLocationPopulatesCache() {
        var cache: CGPoint?
        _ = InputDriver.cachedLocation(using: &cache)
        // If running in CI without UI, location may be nil; just assert cache mirrors result.
        #expect(cache == InputDriver.currentLocation())
    }

    @Test("keyboardStroke maps printable ASCII to physical key events")
    @MainActor
    func keyboardStrokeMapsPrintableASCII() throws {
        let lower = try #require(Element.keyboardStroke(for: "a"))
        #expect(lower.keyCode == 0)
        #expect(!lower.flags.contains(.maskShift))

        let upper = try #require(Element.keyboardStroke(for: "A"))
        #expect(upper.keyCode == 0)
        #expect(upper.flags.contains(.maskShift))

        let digit = try #require(Element.keyboardStroke(for: "1"))
        #expect(digit.keyCode == 18)
        #expect(!digit.flags.contains(.maskShift))

        let symbol = try #require(Element.keyboardStroke(for: "!"))
        #expect(symbol.keyCode == 18)
        #expect(symbol.flags.contains(.maskShift))

        let hyphen = try #require(Element.keyboardStroke(for: "-"))
        #expect(hyphen.keyCode == 27)
        #expect(!hyphen.flags.contains(.maskShift))

        let underscore = try #require(Element.keyboardStroke(for: "_"))
        #expect(underscore.keyCode == 27)
        #expect(underscore.flags.contains(.maskShift))
    }

    @Test("keyboardStroke leaves non-ASCII for Unicode fallback")
    @MainActor
    func keyboardStrokeLeavesNonASCIIForUnicodeFallback() {
        #expect(Element.keyboardStroke(for: "é") == nil)
        #expect(Element.keyboardStroke(for: "🙂") == nil)
    }
}
