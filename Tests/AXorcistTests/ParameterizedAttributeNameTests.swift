import ApplicationServices
import Testing
@testable import AXorcist

@Suite("Parameterized Attribute Name Tests", .tags(.safe))
struct ParameterizedAttributeNameTests {
    @Test
    func `typed attributes use the native macOS raw values`() {
        #expect(Attribute<String>.stringForRangeParameterized.rawValue ==
            kAXStringForRangeParameterizedAttribute as String)
        #expect(Attribute<CFRange>.rangeForLineParameterized.rawValue ==
            kAXRangeForLineParameterizedAttribute as String)
        #expect(Attribute<CGRect>.boundsForRangeParameterized.rawValue ==
            kAXBoundsForRangeParameterizedAttribute as String)
        #expect(Attribute<Int>.lineForIndexParameterized.rawValue ==
            kAXLineForIndexParameterizedAttribute as String)
        #expect(Attribute<NSAttributedString>.attributedStringForRangeParameterized.rawValue ==
            kAXAttributedStringForRangeParameterizedAttribute as String)
    }

    @Test
    func `parameterized attribute catalog matches the system constants`() {
        let expected: Set<String> = [
            kAXLineForIndexParameterizedAttribute as String,
            kAXRangeForLineParameterizedAttribute as String,
            kAXStringForRangeParameterizedAttribute as String,
            kAXRangeForPositionParameterizedAttribute as String,
            kAXRangeForIndexParameterizedAttribute as String,
            kAXBoundsForRangeParameterizedAttribute as String,
            kAXRTFForRangeParameterizedAttribute as String,
            kAXAttributedStringForRangeParameterizedAttribute as String,
            kAXStyleRangeForIndexParameterizedAttribute as String,
            AXAttributeNames.kAXCellForColumnAndRowParameterizedAttribute,
            AXAttributeNames.kAXActionDescriptionAttribute,
        ]

        #expect(AXAttributeNames.parameterizedAttributes == expected)
        let allNamesAreNative = AXAttributeNames.parameterizedAttributes.allSatisfy {
            !$0.hasSuffix("Parameterized")
        }
        #expect(allNamesAreNative)
    }
}
