import ApplicationServices
import Testing
@testable import AXorcist

@Suite("AX action execution")
@MainActor
struct ActionExecutionTests {
    private struct UnexpectedActionError: Error {}

    @Test
    func `canonical action owner invokes the system boundary once`() throws {
        let element = Element(AXUIElementCreateSystemWide())
        var invocationCount = 0
        var receivedAction: String?

        let returnedElement = try element.performAction("AXPress") { _, action in
            invocationCount += 1
            receivedAction = action as String
            return .success
        }

        #expect(invocationCount == 1)
        #expect(receivedAction == "AXPress")
        #expect(CFEqual(returnedElement.underlyingElement, element.underlyingElement))
    }

    @Test
    func `canonical action owner preserves native AX errors`() {
        let element = Element(AXUIElementCreateSystemWide())

        #expect(throws: AccessibilitySystemError.self) {
            try element.performAction("AXPress") { _, _ in .cannotComplete }
        }

        do {
            try element.performAction("AXPress") { _, _ in .cannotComplete }
            Issue.record("Expected AccessibilitySystemError")
        } catch let error as AccessibilitySystemError {
            #expect(error.axError == .cannotComplete)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test
    func `utility preserves native AX errors and only generalizes unknown failures`() {
        #expect(
            AXUtilities.axError(forActionError: AccessibilitySystemError(.cannotComplete)) == .cannotComplete)
        #expect(AXUtilities.axError(forActionError: UnexpectedActionError()) == .failure)
    }

    @Test
    func `successful command action skips supported action discovery`() {
        let element = Element(AXUIElementCreateSystemWide())
        var invocationCount = 0
        var discoveryCount = 0

        let response = AXorcist().executeAction(
            action: "AXPress",
            on: element,
            value: nil,
            performer: { _, _ in invocationCount += 1 },
            supportedActions: { _ in
                discoveryCount += 1
                return ["AXPress"]
            })

        #expect(response.status == "success")
        #expect(invocationCount == 1)
        #expect(discoveryCount == 0)
    }

    @Test
    func `unsupported command action discovers diagnostics once after failure`() {
        let element = Element(AXUIElementCreateSystemWide())
        var discoveryCount = 0

        let response = AXorcist().executeAction(
            action: "AXPress",
            on: element,
            value: nil,
            performer: { _, _ in throw AccessibilitySystemError(.actionUnsupported) },
            supportedActions: { _ in
                discoveryCount += 1
                return ["AXRaise"]
            })

        #expect(response.error?.code == .actionNotSupported)
        #expect(response.error?.message.contains("Action is not supported") == true)
        #expect(response.error?.message.contains("Available actions: [AXRaise]") == true)
        #expect(discoveryCount == 1)
    }

    @Test
    func `cannot complete is preserved without retry or discovery`() {
        let element = Element(AXUIElementCreateSystemWide())
        var invocationCount = 0
        var discoveryCount = 0

        let response = AXorcist().executeAction(
            action: "AXPress",
            on: element,
            value: nil,
            performer: { _, _ in
                invocationCount += 1
                throw AccessibilitySystemError(.cannotComplete)
            },
            supportedActions: { _ in
                discoveryCount += 1
                return nil
            })

        #expect(response.error?.code == .actionFailed)
        #expect(response.error?.message.contains("Cannot complete operation") == true)
        #expect(response.error?.message.contains("-25204") == true)
        #expect(invocationCount == 1)
        #expect(discoveryCount == 0)
    }

    @Test(arguments: [
        (AXError.apiDisabled, AXErrorCode.permissionDenied),
        (.invalidUIElement, .elementNotFound),
        (.actionUnsupported, .actionNotSupported),
        (.illegalArgument, .invalidParameter),
        (.cannotComplete, .actionFailed),
    ])
    func `native action failures map to precise response codes`(_ error: AXError, _ code: AXErrorCode) {
        #expect(error.actionResponseCode == code)
    }
}
