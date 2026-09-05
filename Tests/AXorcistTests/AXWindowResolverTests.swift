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

    @Test
    @MainActor
    func `findWindow asks the window list with the requested messaging timeout`() {
        var seenTimeout: Float?
        let result = self.resolver.findWindow(
            by: 1,
            in: NSRunningApplication.current,
            messagingTimeout: 1.25)
        { _, timeout in
            seenTimeout = timeout
            return nil
        }

        #expect(result == nil)
        #expect(seenTimeout == 1.25)
    }

    @Test(arguments: [Float.zero, -0.1, Float.infinity, Float.nan])
    @MainActor
    func `findWindow returns nil when the messaging timeout is invalid`(timeout: Float) {
        #expect(self.resolver.findWindow(
            by: 1,
            in: NSRunningApplication.current,
            messagingTimeout: timeout) == nil)
    }
}
