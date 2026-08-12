import AppKit
import ApplicationServices
import Foundation
import Testing
@testable import AXorcist

@Suite("Parameterized Attribute Conversion Tests", .tags(.safe))
@MainActor
struct ParameterizedAttributeConversionTests {
    @Test
    func `Attributed strings preserve their native result type`() throws {
        let element = Element(AXUIElementCreateSystemWide())
        let expected = NSAttributedString(
            string: "Hello",
            attributes: [.foregroundColor: NSColor.systemBlue])
        let rawValue = expected as CFAttributedString

        let converted: NSAttributedString? = element.convertCFTypeToSwiftType(
            rawValue,
            attribute: .attributedStringForRangeParameterized)

        #expect(try #require(converted).isEqual(to: expected))
    }

    @Test
    func `Attributed strings still project to plain strings when requested`() {
        let element = Element(AXUIElementCreateSystemWide())
        let rawValue = NSAttributedString(string: "Hello") as CFAttributedString
        let stringAttribute = Attribute<String>(
            AXAttributeNames.kAXAttributedStringForRangeParameterizedAttribute)

        let converted: String? = element.convertCFTypeToSwiftType(
            rawValue,
            attribute: stringAttribute)

        #expect(converted == "Hello")
    }

    @Test
    func `CFRange parameters use a native AXValue`() throws {
        let element = Element(AXUIElementCreateSystemWide())
        let expected = CFRange(location: 7, length: 11)

        let bridged = try #require(element.convertParameterToCFTypeRef(
            expected,
            attribute: Attribute<String>.stringForRangeParameterized))
        #expect(CFGetTypeID(bridged) == AXValueGetTypeID())

        let axValue = unsafeDowncast(bridged, to: AXValue.self)
        let actual = try #require(axValue.cfRange())
        #expect(axValue.valueType == .cfRange)
        #expect(actual.location == expected.location)
        #expect(actual.length == expected.length)
    }

    @Test
    func `Element parameters preserve their underlying accessibility identity`() throws {
        let receiver = Element(AXUIElementCreateSystemWide())
        let expected = Element(AXUIElementCreateApplication(2_000_000_123))

        let bridged = try #require(receiver.convertParameterToCFTypeRef(
            expected,
            attribute: Attribute<AXUIElement>.cellForColumnAndRowParameterized))

        #expect(CFGetTypeID(bridged) == AXUIElementGetTypeID())
        #expect(CFEqual(bridged, expected.underlyingElement))
    }
}
