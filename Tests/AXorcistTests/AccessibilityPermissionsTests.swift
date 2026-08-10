import ApplicationServices
import Testing
@testable import AXorcist

@MainActor
struct AccessibilityPermissionsTests {
    @Test
    func `Native automation permission mapping is noninteractive and truthful`() {
        let granted = automationPermissionResult(for: noErr, bundleID: "com.example.Test")
        #expect(granted.status == true)
        #expect(granted.errorMessage == nil)

        let undecided = automationPermissionResult(
            for: OSStatus(errAEEventWouldRequireUserConsent),
            bundleID: "com.example.Test")
        #expect(undecided.status == false)
        #expect(undecided.errorMessage?.contains("not been determined") == true)

        let denied = automationPermissionResult(
            for: OSStatus(errAEEventNotPermitted),
            bundleID: "com.example.Test")
        #expect(denied.status == false)
        #expect(denied.errorMessage?.contains("denied") == true)

        let missing = automationPermissionResult(for: OSStatus(procNotFound), bundleID: "com.example.Test")
        #expect(missing.status == nil)
        #expect(missing.errorMessage == nil)
    }
}
