import AppKit
import CoreGraphics
@testable import AXorcist
import Testing

@Suite("AXWindowResolver")
struct AXWindowResolverTests {
    private let resolver = AXWindowResolver()

    @Test("windowID returns nil for non-window element")
    @MainActor
    func windowIdNilForNonWindow() async {
        let systemWide = AXUIElementCreateSystemWide()
        let element = Element(systemWide)
        #expect(self.resolver.windowID(from: element) == nil)
    }

    @Test("windowExists false for random ID")
    func windowExistsFalse() {
        #expect(self.resolver.windowExists(windowID: 999_999_999) == false)
    }
}
