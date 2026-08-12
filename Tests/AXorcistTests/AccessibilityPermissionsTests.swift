import Testing
@testable import AXorcist

@MainActor
struct AccessibilityPermissionsTests {
    @Test
    func `Permission status reports Accessibility without legacy automation probes`() {
        let status = getPermissionsStatus()

        #expect(status.canUseAccessibility == (
            status.isAccessibilityApiEnabled && status.isProcessTrustedForAccessibility))
        #expect(status.overallErrorMessages.isEmpty)
    }

    @available(*, deprecated, message: "Exercises the retained legacy compatibility surface.")
    @Test
    func `Legacy automation targets remain source compatible but unknown`() {
        let status = getPermissionsStatus(checkAutomationFor: ["com.example.Test"])

        #expect(status.automationStatus.isEmpty)
        #expect(status.canAutomate(bundleID: "com.example.Test") == nil)
        #expect(status.overallErrorMessages.isEmpty)
    }
}
