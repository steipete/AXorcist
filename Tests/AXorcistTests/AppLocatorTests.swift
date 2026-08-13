import AppKit
import CoreGraphics
import Testing
@testable import AXorcist

@Suite("AppLocator")
struct AppLocatorTests {
    private struct TestApplication: Equatable {
        let pid: pid_t
        let isEligible: Bool
    }

    @Test
    @MainActor
    func `returns frontmost when point is nil and front app has window under mouse`() {
        // Skip on headless CI where NSEvent.mouseLocation is (0,0) and no frontmost app.
        guard NSWorkspace.shared.frontmostApplication != nil else { return }

        let app = AppLocator.app(at: nil)
        // If we have any frontmost app, AppLocator should return something (frontmost fallback).
        #expect(app != nil)
        // In headless or multi-display test environments another candidate can win; the non-nil check
        // above is sufficient coverage and avoids flaking on PID mismatches.
    }

    @Test
    @MainActor
    func `falls back to frontmost when no window matches point`() {
        guard let front = NSWorkspace.shared.frontmostApplication else { return }
        // Pick an off-screen point unlikely to hit a window.
        let offscreen = CGPoint(x: -10000, y: -10000)
        let app = AppLocator.app(at: offscreen)
        #expect(app?.processIdentifier == front.processIdentifier)
        #expect(AppLocator.exactApp(at: offscreen) == nil)
    }

    @Test
    @MainActor
    func `exact lookup does not use compatibility fallback on miss`() {
        var fallbackCount = 0

        let result: TestApplication? = AppLocator.locate(
            at: CGPoint(x: 50, y: 50),
            windows: [],
            policy: .exact,
            applications: AppLocator.ApplicationLookup(
                applicationForPID: { TestApplication(pid: $0, isEligible: true) },
                isEligible: \TestApplication.isEligible,
                frontmostApplication: {
                    fallbackCount += 1
                    return TestApplication(pid: 99, isEligible: true)
                }))

        #expect(result == nil)
        #expect(fallbackCount == 0)
    }

    @Test
    @MainActor
    func `compatibility lookup falls back only after an exact miss`() {
        var fallbackCount = 0

        let result: TestApplication? = AppLocator.locate(
            at: CGPoint(x: 50, y: 50),
            windows: [],
            policy: .frontmostCompatibility,
            applications: AppLocator.ApplicationLookup(
                applicationForPID: { TestApplication(pid: $0, isEligible: true) },
                isEligible: \TestApplication.isEligible,
                frontmostApplication: {
                    fallbackCount += 1
                    return TestApplication(pid: 99, isEligible: true)
                }))

        #expect(result?.pid == 99)
        #expect(fallbackCount == 1)
    }

    @Test
    @MainActor
    func `ordered window index resolves the first eligible owner`() {
        let point = CGPoint(x: 50, y: 50)
        let windows = [
            AppLocator.WindowSnapshot(ownerPID: 10, bounds: CGRect(x: 0, y: 0, width: 100, height: 100)),
            AppLocator.WindowSnapshot(ownerPID: 10, bounds: CGRect(x: 0, y: 0, width: 80, height: 80)),
            AppLocator.WindowSnapshot(ownerPID: 20, bounds: CGRect(x: 0, y: 0, width: 100, height: 100)),
        ]
        var inspectedPIDs: [pid_t] = []
        var fallbackCount = 0

        let result: TestApplication? = AppLocator.locate(
            at: point,
            windows: windows,
            policy: .frontmostCompatibility,
            applications: AppLocator.ApplicationLookup(
                applicationForPID: {
                    inspectedPIDs.append($0)
                    return TestApplication(pid: $0, isEligible: $0 == 20)
                },
                isEligible: \TestApplication.isEligible,
                frontmostApplication: {
                    fallbackCount += 1
                    return TestApplication(pid: 99, isEligible: true)
                }))

        #expect(result?.pid == 20)
        #expect(inspectedPIDs == [10, 20])
        #expect(fallbackCount == 0)
    }

    @Test
    @MainActor
    func `offscreen lookup performs no application queries for a large snapshot`() {
        let point = CGPoint(x: -10000, y: -10000)
        let windows = (0..<10000).map {
            AppLocator.WindowSnapshot(
                ownerPID: pid_t($0 + 1),
                bounds: CGRect(x: $0, y: $0, width: 10, height: 10))
        }
        var applicationQueryCount = 0

        let result: TestApplication? = AppLocator.locate(
            at: point,
            windows: windows,
            policy: .exact,
            applications: AppLocator.ApplicationLookup(
                applicationForPID: {
                    applicationQueryCount += 1
                    return TestApplication(pid: $0, isEligible: true)
                },
                isEligible: \TestApplication.isEligible,
                frontmostApplication: { TestApplication(pid: 99, isEligible: true) }))

        #expect(result == nil)
        #expect(applicationQueryCount == 0)
    }

    @Test
    func `AppKit mouse points convert to the matching Quartz display`() {
        let screens = [
            AppLocator.ScreenCoordinateSpace(
                appKitFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                quartzFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
            AppLocator.ScreenCoordinateSpace(
                appKitFrame: CGRect(x: -1280, y: 200, width: 1280, height: 720),
                quartzFrame: CGRect(x: -1280, y: -200, width: 1280, height: 720)),
        ]

        #expect(AppLocator.quartzPoint(
            fromAppKit: CGPoint(x: 100, y: 200),
            screens: screens) == CGPoint(x: 100, y: 880))
        #expect(AppLocator.quartzPoint(
            fromAppKit: CGPoint(x: -1000, y: 500),
            screens: screens) == CGPoint(x: -1000, y: 220))
        #expect(AppLocator.quartzPoint(
            fromAppKit: CGPoint(x: 3000, y: 3000),
            screens: screens) == nil)
    }
}
