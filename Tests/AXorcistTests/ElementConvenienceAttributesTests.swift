import ApplicationServices
import Testing
@testable import AXorcist

@Suite("Element Convenience Attribute Tests", .tags(.safe))
struct ElementConvenienceAttributesTests {
    @MainActor
    @Test(.tags(.safe))
    func `Selected text range setter returns the native AX error`() throws {
        let element = Element(AXUIElementCreateSystemWide())
        let range = CFRange(location: 1, length: 2)
        let axValue = try #require(AXValue.create(range: range))
        let nativeError = AXUIElementSetAttributeValue(
            element.underlyingElement,
            AXAttributeNames.kAXSelectedTextRangeAttribute as CFString,
            axValue)

        let wrapperError = element.setSelectedTextRange(range)

        #expect(nativeError != .success)
        #expect(wrapperError == nativeError)
    }
}
