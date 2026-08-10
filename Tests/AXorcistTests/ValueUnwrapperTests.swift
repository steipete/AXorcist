import ApplicationServices
import Testing
@testable import AXorcist

@Suite("ValueUnwrapper Tests", .tags(.safe))
struct ValueUnwrapperTests {
    @MainActor
    @Test(.tags(.safe))
    func `unwrap preserves CFRange AXValue`() {
        let expected = CFRange(location: 12, length: 34)
        guard let axValue = AXValue.create(range: expected) else {
            Issue.record("Failed to create AXValue from CFRange")
            return
        }

        #expect(axValue.valueType == .cfRange)
        #expect(axValue.cfRange()?.location == expected.location)
        #expect(axValue.cfRange()?.length == expected.length)

        guard let actual = ValueUnwrapper.unwrap(axValue) as? CFRange else {
            Issue.record("Expected ValueUnwrapper to return a CFRange")
            return
        }

        #expect(actual.location == expected.location)
        #expect(actual.length == expected.length)
    }
}
