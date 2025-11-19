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
        var cache: CGPoint? = nil
        _ = InputDriver.cachedLocation(using: &cache)
        // If running in CI without UI, location may be nil; just assert cache mirrors result.
        #expect(cache == InputDriver.currentLocation())
    }
}
