import ApplicationServices
import Testing
@testable import AXorcist

@Suite("AX value execution")
@MainActor
struct SetValueExecutionTests {
    nonisolated enum InvalidValueFixture: CaseIterable, Sendable {
        case missing
        case integer
        case boolean
    }

    @Test
    func `canonical value owner invokes the native setter once`() throws {
        let element = Element(AXUIElementCreateSystemWide())
        var invocationCount = 0
        var receivedAttribute: String?
        var receivedValue: String?

        let returnedElement = try element.setAttributeValue(
            "hello",
            forAttribute: AXAttributeNames.kAXValueAttribute)
        { _, attribute, value in
            invocationCount += 1
            receivedAttribute = attribute as String
            receivedValue = value as? String
            return .success
        }

        #expect(invocationCount == 1)
        #expect(receivedAttribute == AXAttributeNames.kAXValueAttribute)
        #expect(receivedValue == "hello")
        #expect(CFEqual(returnedElement.underlyingElement, element.underlyingElement))
    }

    @Test
    func `canonical value owner preserves native AX errors`() {
        let element = Element(AXUIElementCreateSystemWide())

        do {
            try element.setAttributeValue("hello", forAttribute: AXAttributeNames.kAXValueAttribute) { _, _, _ in
                .attributeUnsupported
            }
            Issue.record("Expected AccessibilitySystemError")
        } catch let error as AccessibilitySystemError {
            #expect(error.axError == .attributeUnsupported)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test
    func `AXSetValue compatibility command uses only the value setter`() {
        let element = Element(AXUIElementCreateSystemWide())
        var actionCount = 0
        var valueSetCount = 0
        var discoveryCount = 0
        var receivedValue: String?

        let response = AXorcist().executeResolvedAction(
            command: Self.command(value: AnyCodable("hello")),
            on: element,
            performer: { _, _ in actionCount += 1 },
            valueSetter: { _, value in
                valueSetCount += 1
                receivedValue = value
            },
            supportedActions: { _ in
                discoveryCount += 1
                return [AXActionNames.kAXSetValueAction]
            })

        #expect(response.status == "success")
        #expect(actionCount == 0)
        #expect(valueSetCount == 1)
        #expect(discoveryCount == 0)
        #expect(receivedValue == "hello")
    }

    @Test(arguments: InvalidValueFixture.allCases)
    func `AXSetValue rejects missing or non-string values before dispatch`(_ fixture: InvalidValueFixture) {
        let element = Element(AXUIElementCreateSystemWide())
        var actionCount = 0
        var valueSetCount = 0
        var discoveryCount = 0
        let value: AnyCodable? = switch fixture {
        case .missing: nil
        case .integer: AnyCodable(42)
        case .boolean: AnyCodable(true)
        }

        let response = AXorcist().executeResolvedAction(
            command: Self.command(value: value),
            on: element,
            performer: { _, _ in actionCount += 1 },
            valueSetter: { _, _ in valueSetCount += 1 },
            supportedActions: { _ in
                discoveryCount += 1
                return nil
            })

        #expect(response.error?.code == .invalidParameter)
        #expect(response.error?.message.contains("No value was dispatched") == true)
        #expect(actionCount == 0)
        #expect(valueSetCount == 0)
        #expect(discoveryCount == 0)
    }

    @Test
    func `AXSetValue preserves exact native setter failures`() {
        let element = Element(AXUIElementCreateSystemWide())
        var valueSetCount = 0

        let response = AXorcist().executeResolvedAction(
            command: Self.command(value: AnyCodable("hello")),
            on: element,
            valueSetter: { _, _ in
                valueSetCount += 1
                throw AccessibilitySystemError(.attributeUnsupported)
            })

        #expect(response.error?.code == .attributeNotFound)
        #expect(response.error?.message.contains("Attribute is not supported") == true)
        #expect(response.error?.message.contains("-25205") == true)
        #expect(valueSetCount == 1)
    }

    @Test
    func `legacy value utility rejects nil before dispatch`() {
        let result = AXUtilities.performSetValueAction(
            forElement: Element(AXUIElementCreateSystemWide()),
            valueToSet: nil)

        #expect(result.error == .illegalArgument)
        #expect(result.errorMessage?.contains("non-nil value") == true)
    }

    @Test(arguments: [
        (AXError.apiDisabled, AXErrorCode.permissionDenied),
        (.invalidUIElement, .elementNotFound),
        (.attributeUnsupported, .attributeNotFound),
        (.illegalArgument, .invalidParameter),
        (.cannotComplete, .actionFailed),
    ])
    func `native value failures map to precise response codes`(_ error: AXError, _ code: AXErrorCode) {
        #expect(error.valueResponseCode == code)
    }

    private static func command(value: AnyCodable?) -> PerformActionCommand {
        PerformActionCommand(
            appIdentifier: "com.example.fixture",
            locator: Locator(criteria: []),
            action: AXActionNames.kAXSetValueAction,
            value: value)
    }
}
