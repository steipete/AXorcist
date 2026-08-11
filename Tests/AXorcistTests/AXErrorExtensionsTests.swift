import ApplicationServices
import Testing
@testable import AXorcist

@Suite("AXError extensions")
struct AXErrorExtensionsTests {
    @Test
    func `localized descriptions are available outside the main actor`() {
        #expect(Self.describe(.actionUnsupported) == "Action is not supported")
    }

    private nonisolated static func describe(_ error: AXError) -> String {
        error.localizedDescription
    }
}
