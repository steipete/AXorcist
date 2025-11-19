import AppKit
import CoreGraphics
@testable import AXorcist
import Testing

@Suite("AppLocator")
struct AppLocatorTests {
    @Test("returns frontmost when point is nil and front app has window under mouse")
    @MainActor
    func frontmostPreferred() async throws {
        // Skip on headless CI where NSEvent.mouseLocation is (0,0) and no frontmost app.
        guard let front = NSWorkspace.shared.frontmostApplication else { return }

        let app = AppLocator.app(at: nil)
        // If we have any frontmost app, AppLocator should return something (frontmost fallback).
        #expect(app != nil)
        // Best-effort check: if the frontmost app is the only candidate, expect it.
        #expect(app?.processIdentifier == front.processIdentifier)
    }

    @Test("falls back to frontmost when no window matches point")
    @MainActor
    func fallbackToFrontmost() async throws {
        guard let front = NSWorkspace.shared.frontmostApplication else { return }
        // Pick an off-screen point unlikely to hit a window.
        let offscreen = CGPoint(x: -10_000, y: -10_000)
        let app = AppLocator.app(at: offscreen)
        #expect(app?.processIdentifier == front.processIdentifier)
    }
}
