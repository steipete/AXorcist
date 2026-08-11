import AppKit
import CoreGraphics
import Testing
@testable import AXorcist

@Suite("AXWindowResolver")
struct AXWindowResolverTests {
    private let resolver = AXWindowResolver()

    @Test
    @MainActor
    func `windowID returns nil for non-window element`() {
        let systemWide = AXUIElementCreateSystemWide()
        let element = Element(systemWide)
        #expect(self.resolver.windowID(from: element) == nil)
    }

    @Test
    func `windowExists false for random ID`() {
        #expect(self.resolver.windowExists(windowID: 999_999_999) == false)
    }
}
