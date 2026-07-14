import ApplicationServices
import Testing
@testable import AXorcist

@Suite("AXError extensions")
struct AXErrorExtensionsTests {
    @Test("localized descriptions are available outside the main actor")
    func localizedDescriptionIsNonisolated() {
        #expect(Self.describe(.actionUnsupported) == "Action is not supported")
    }

    nonisolated private static func describe(_ error: AXError) -> String {
        error.localizedDescription
    }
}
