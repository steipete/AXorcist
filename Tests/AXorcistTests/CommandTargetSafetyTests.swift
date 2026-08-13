import ApplicationServices
import CoreGraphics
import Testing
@testable import AXorcist

@Suite("Command target safety")
@MainActor
struct CommandTargetSafetyTests {
    @Test
    func `point lookup rejects conflicting selectors before resolution`() {
        var applicationResolutionCount = 0
        var pointLookupCount = 0
        let command = GetElementAtPointCommand(
            point: CGPoint(x: 10, y: 20),
            appIdentifier: "com.example.fixture",
            pid: 42)

        let response = AXorcist().executeGetElementAtPoint(
            command: command,
            applicationResolver: { _ in
                applicationResolutionCount += 1
                return nil
            },
            elementResolver: { _, _ in
                pointLookupCount += 1
                return nil
            })

        #expect(response.error?.code == .invalidParameter)
        #expect(applicationResolutionCount == 0)
        #expect(pointLookupCount == 0)
    }

    @Test
    func `missing PID target cannot fall back to focused application`() {
        let expectedPID: pid_t = 42424
        var resolvedTarget: AXApplicationTarget?
        var pointLookupCount = 0
        let command = GetElementAtPointCommand(
            point: CGPoint(x: 10, y: 20),
            pid: Int(expectedPID))

        let response = AXorcist().executeGetElementAtPoint(
            command: command,
            applicationResolver: { target in
                resolvedTarget = target
                return nil
            },
            elementResolver: { _, _ in
                pointLookupCount += 1
                return nil
            })

        #expect(resolvedTarget == .process(expectedPID))
        #expect(response.error?.code == .applicationNotFound)
        #expect(pointLookupCount == 0)
    }

    @Test
    func `missing point element is an error`() {
        let expectedPID: pid_t = 54321
        let application = Element(AXUIElementCreateApplication(expectedPID))
        var receivedPID: pid_t?
        let command = GetElementAtPointCommand(
            point: CGPoint(x: 10, y: 20),
            pid: Int(expectedPID))

        let response = AXorcist().executeGetElementAtPoint(
            command: command,
            applicationResolver: { target in
                #expect(target == .process(expectedPID))
                return application
            },
            elementResolver: { _, pid in
                receivedPID = pid
                return nil
            })

        #expect(receivedPID == expectedPID)
        #expect(response.status == "error")
        #expect(response.error?.code == .elementNotFound)
    }
}
