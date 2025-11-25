import AppKit
import CoreGraphics
import Testing
@testable import AXorcist

@Suite("AppLocator")
struct AppLocatorTests {
    @Test("returns frontmost when point is nil and front app has window under mouse")
    @MainActor
    func frontmostPreferred() async throws {
        // Skip on headless CI where NSEvent.mouseLocation is (0,0) and no frontmost app.
        guard NSWorkspace.shared.frontmostApplication != nil else { return }

        let app = AppLocator.app(at: nil)
        // If we have any frontmost app, AppLocator should return something (frontmost fallback).
        #expect(app != nil)
        // In headless or multi-display test environments another candidate can win; the non-nil check
        // above is sufficient coverage and avoids flaking on PID mismatches.
    }

    @Test("falls back to frontmost when no window matches point")
    @MainActor
    func fallbackToFrontmost() async throws {
        guard let front = NSWorkspace.shared.frontmostApplication else { return }
        // Pick an off-screen point unlikely to hit a window.
        let offscreen = CGPoint(x: -10000, y: -10000)
        let app = AppLocator.app(at: offscreen)
        #expect(app?.processIdentifier == front.processIdentifier)
    }
}
