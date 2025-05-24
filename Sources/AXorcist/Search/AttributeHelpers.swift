// AttributeHelpers.swift - Contains functions for fetching and formatting element attributes

import ApplicationServices // For AXUIElement related types
import CoreGraphics // For potential future use with geometry types from attributes
import Foundation

// ElementDetails struct for AXpector
public struct ElementDetails {
    public var title: String?
    public var role: String?
    public var roleDescription: String?
    public var value: Any?
    public var help: Any?
    public var isIgnored: Bool
    public var actions: [String]?
    public var isClickable: Bool
    public var computedName: String?

    public init() {
        self.isIgnored = false
        self.isClickable = false
    }
}

// Enum to specify the source of an attribute
public enum AttributeSource: String, Codable {
    case direct // Directly from AXUIElement
    case computed // Computed by AXorcist (e.g., path, name heuristic)
    case prefetched // From element's stored attributes dictionary
}

// Struct to hold attribute data along with its source
public struct AttributeData: Codable {
    public let value: AnyCodable
    public let source: AttributeSource
}

// Helper functions to convert CoreGraphics types to dictionaries for JSON serialization
// These are needed because AnyCodable might not handle them directly as dictionaries.
func NSPointToDictionary(_ point: CGPoint) -> [String: CGFloat] {
    return ["x": point.x, "y": point.y]
}

func NSSizeToDictionary(_ size: CGSize) -> [String: CGFloat] {
    return ["width": size.width, "height": size.height]
}

func NSRectToDictionary(_ rect: CGRect) -> [String: Any] { // Changed to Any for origin/size
    return [
        "x": rect.origin.x,
        "y": rect.origin.y,
        "width": rect.size.width,
        "height": rect.size.height
    ]
}

// MARK: - Element Summary Helpers

// Removed getSingleElementSummary as it was unused.

// MARK: - Internal Fetch Logic Helpers

// Approach using direct property access within a switch statement
@MainActor
private func extractDirectPropertyValue(
    for attributeName: String,
    from element: Element,
    outputFormat: OutputFormat
) -> (value: Any?, handled: Bool) {
    var extractedValue: Any?
    var handled = true

    switch attributeName {
    case AXAttributeNames.kAXPathHintAttribute:
        extractedValue = element.attribute(Attribute<String>(AXAttributeNames.kAXPathHintAttribute))
    case AXAttributeNames.kAXRoleAttribute:
        extractedValue = element.role()
    case AXAttributeNames.kAXSubroleAttribute:
        extractedValue = element.subrole()
    case AXAttributeNames.kAXTitleAttribute:
        extractedValue = element.title()
    case AXAttributeNames.kAXDescriptionAttribute:
        extractedValue = element.descriptionText() // Renamed
    case AXAttributeNames.kAXEnabledAttribute:
        let val = element.isEnabled()
        extractedValue = val
        if outputFormat == .textContent {
            extractedValue = val?.description ?? AXMiscConstants.kAXNotAvailableString
        }
    case AXAttributeNames.kAXFocusedAttribute:
        let val = element.isFocused()
        extractedValue = val
        if outputFormat == .textContent {
            extractedValue = val?.description ?? AXMiscConstants.kAXNotAvailableString
        }
    case AXAttributeNames.kAXHiddenAttribute:
        let val = element.isHidden()
        extractedValue = val
        if outputFormat == .textContent {
            extractedValue = val?.description ?? AXMiscConstants.kAXNotAvailableString
        }
    case AXMiscConstants.isIgnoredAttributeKey:
        let val = element.isIgnored()
        extractedValue = val
        if outputFormat == .textContent {
            extractedValue = val ? "true" : "false"
        }
    case "PID":
        let val = element.pid()
        extractedValue = val
        if outputFormat == .textContent {
            extractedValue = val?.description ?? AXMiscConstants.kAXNotAvailableString
        }
    case AXAttributeNames.kAXElementBusyAttribute:
        let val = element.isElementBusy()
        extractedValue = val
        if outputFormat == .textContent {
            extractedValue = val?.description ?? AXMiscConstants.kAXNotAvailableString
        }
    default:
        handled = false
    }
    return (extractedValue, handled)
}

@MainActor
private func determineAttributesToFetch(
    requestedAttributes: [String]?,
    forMultiDefault: Bool,
    targetRole: String?,
    element: Element
) -> [String] {
    var attributesToFetch = requestedAttributes ?? []
    if forMultiDefault {
        attributesToFetch = [
            AXAttributeNames.kAXRoleAttribute,
            AXAttributeNames.kAXValueAttribute,
            AXAttributeNames.kAXTitleAttribute,
            AXAttributeNames.kAXIdentifierAttribute
        ]
        if let role = targetRole, role == AXRoleNames.kAXStaticTextRole {
            attributesToFetch = [
                AXAttributeNames.kAXRoleAttribute,
                AXAttributeNames.kAXValueAttribute,
                AXAttributeNames.kAXIdentifierAttribute
            ]
        }
    } else if attributesToFetch.isEmpty {
        var attrNames: CFArray?
        if AXUIElementCopyAttributeNames(element.underlyingElement, &attrNames) == .success,
           let names = attrNames as? [String] {
            attributesToFetch.append(contentsOf: names)
            axDebugLog(
                "determineAttributesToFetch: No specific attributes requested, " +
                    "fetched all \(names.count) available: \(names.joined(separator: ", "))"
            )
        } else {
            axDebugLog(
                "determineAttributesToFetch: No specific attributes requested and " +
                    "failed to fetch all available names."
            )
        }
    }
    return attributesToFetch
}

// MARK: - Public Attribute Getters

@MainActor
public func getElementAttributes(
    element: Element,
    attributes attrNames: [String],
    outputFormat: OutputFormat,
    valueFormatOption: ValueFormatOption = .default
    // Removed old logging params & forMultiDefault/targetRole
) -> ([String: AnyCodable], [AXLogEntry]) {
    // Return type is now ([String: AnyCodable], [AXLogEntry]) as per original, but logs will be empty.
    var result: [String: AnyCodable] = [:]

    let requestingStr = attrNames.isEmpty ? "all" : attrNames.joined(separator: ", ")
    axDebugLog(
        "getElementAttributes called for element: \(element.briefDescription(option: .short)), " +
            "requesting: \(requestingStr)"
    )

    let attributesToProcess = attrNames.isEmpty ? (element.attributeNames() ?? []) : attrNames

    for attr in attributesToProcess {
        if attr == AXAttributeNames.kAXParentAttribute {
            let parent = element.parent()
            result[AXAttributeNames.kAXParentAttribute] = formatParentAttribute(
                parent,
                outputFormat: outputFormat,
                valueFormatOption: valueFormatOption
            )
        } else if attr == AXAttributeNames.kAXChildrenAttribute {
            let children = element.children()
            result[attr] = formatChildrenAttribute(
                children,
                outputFormat: outputFormat,
                valueFormatOption: valueFormatOption
            )
        } else if attr == AXAttributeNames.kAXFocusedUIElementAttribute {
            let focused = element.focusedElement()
            result[attr] = formatFocusedUIElementAttribute(
                focused,
                outputFormat: outputFormat,
                valueFormatOption: valueFormatOption
            )
        } else {
            // Use the refactored extractAndFormatAttribute.
            // The knownAttributes parameter is passed as empty as this function doesn't use that logic directly.
            if let formattedValue = extractAndFormatAttribute(
                element: element,
                attributeName: attr,
                outputFormat: outputFormat,
                valueFormatOption: valueFormatOption,
                knownAttributes: [:]
            ) {
                result[attr] = formattedValue
            } else {
                if outputFormat != .textContent { // For non-text, represent nil explicitly
                    result[attr] = AnyCodable(nil as String?)
                }
                // Log if important, e.g., if an attribute was specifically requested but not found/formatted
                if attrNames.contains(attr) { // only log if it was explicitly requested
                    axDebugLog(
                        "Attribute '\(attr)' specifically requested but resulted in " +
                            "nil or no value after formatting."
                    )
                }
            }
        }
    }

    // Add computed properties based on outputFormat
    if outputFormat != .textContent {
        if result[AXMiscConstants.computedNameAttributeKey] == nil {
            if let name = element.computedName() {
                result[AXMiscConstants.computedNameAttributeKey] = AnyCodable(name)
            }
        }
        if result[AXMiscConstants.isClickableAttributeKey] == nil {
            let isButton = (element.role() == AXRoleNames.kAXButtonRole)
            let hasPressAction = element.isActionSupported(AXActionNames.kAXPressAction)
            if isButton || hasPressAction {
                result[AXMiscConstants.isClickableAttributeKey] = AnyCodable(true)
            }
        }
    }
    if outputFormat == .verbose && result[AXMiscConstants.computedPathAttributeKey] == nil {
        let path = element.generatePathString()
        result[AXMiscConstants.computedPathAttributeKey] = AnyCodable(path)
    }

    axDebugLog(
        "getElementAttributes finished for element: \(element.briefDescription(option: .short)). " +
            "Returning \(result.count) attributes."
    )
    return (result, []) // Return empty logs, global logger is used.
}

@MainActor
public func getAllElementDataForAXpector(
    for element: Element,
    outputFormat: OutputFormat = .jsonString, // Typically .jsonString for AXpector
    valueFormatOption: ValueFormatOption = .default
) -> ([String: AnyCodable], ElementDetails) {

    var attributes: [String: AnyCodable] = [:]
    var elementDetails = ElementDetails()

    let allAttributeNames = element.attributeNames() ?? []
    axDebugLog(
        "getAllElementDataForAXpector: Fetching \(allAttributeNames.count) attributes for " +
            "\(element.briefDescription(option: .short))."
    )

    for attrName in allAttributeNames {
        if attrName == AXAttributeNames.kAXChildrenAttribute || attrName == AXAttributeNames.kAXParentAttribute {
            continue
        }
        if AXAttributeNames.parameterizedAttributes.contains(attrName) {
            continue
        }

        let rawCFValue = element.rawAttributeValue(named: attrName)
        let swiftValue = rawCFValue.flatMap { ValueUnwrapper.unwrap($0) }
        attributes[attrName] = AnyCodable(swiftValue)
    }

    elementDetails.title = element.title()
    elementDetails.role = element.role()
    elementDetails.roleDescription = element.roleDescription()
    elementDetails.value = attributes[AXAttributeNames.kAXValueAttribute]?.value
    elementDetails.help = attributes[AXAttributeNames.kAXHelpAttribute]?.value
    elementDetails.isIgnored = element.isIgnored()

    var actionsToStore: [String]?
    if let currentActions = element.supportedActions(), !currentActions.isEmpty {
        actionsToStore = currentActions
    } else {
        if let fallbackActions: [String] = element.attribute(
            Attribute<[String]>(AXAttributeNames.kAXActionsAttribute)
        ), !fallbackActions.isEmpty {
            actionsToStore = fallbackActions
        }
    }
    elementDetails.actions = actionsToStore

    let pressActionSupported = element.isActionSupported(AXActionNames.kAXPressAction)
    let hasPressAction = elementDetails.actions?.contains(AXActionNames.kAXPressAction) ?? false
    elementDetails.isClickable = hasPressAction || pressActionSupported

    if let name = element.computedName() {
        let attributeData = AttributeData(value: AnyCodable(name), source: .computed)
        attributes[AXMiscConstants.computedNameAttributeKey] = AnyCodable(attributeData)
    }
    elementDetails.computedName = element.computedName()
    axDebugLog("getAllElementDataForAXpector: Finished processing for \(element.briefDescription(option: .short)).")
    return (attributes, elementDetails)
}

// Function to get specifically computed attributes for an element
@MainActor
internal func getComputedAttributes(for element: Element) -> [String: AttributeData] {
    var computedAttrs: [String: AttributeData] = [:]

    if let name = element.computedName() { // element.computedName() uses GlobalAXLogger
        computedAttrs[AXMiscConstants.computedNameAttributeKey] = AttributeData(
            value: AnyCodable(name),
            source: .computed
        )
        axDebugLog(
            "getComputedAttributes: Computed name for element " +
                "\(element.briefDescription(option: .short)) is '\(name)'.",
            file: #file,
            function: #function,
            line: #line
        )
    } else {
        axDebugLog(
            "getComputedAttributes: Element \(element.briefDescription(option: .short)) " +
                "has no computed name.",
            file: #file,
            function: #function,
            line: #line
        )
    }

    // Placeholder for other future purely computed attributes if needed
    // For example, isClickable could also be added here if not handled elsewhere:
    // let isButton = (element.role() == AXRoleNames.kAXButtonRole)
    // let hasPressAction = element.isActionSupported(AXActionNames.kAXPressAction)
    // if isButton || hasPressAction {
    //     computedAttrs[AXMiscConstants.isClickableAttributeKey] = AttributeData(
    //         value: AnyCodable(true), source: .computed
    //     )
    // }

    return computedAttrs
}

// Helper for formatting raw CFTypeRef values for .textContent output
@MainActor
internal func formatRawCFValueForTextContent(_ rawValue: CFTypeRef?) -> String {
    guard let value = rawValue else { return AXMiscConstants.kAXNotAvailableString }
    let typeID = CFGetTypeID(value)
    if typeID == CFStringGetTypeID() {
        return (value as! String)
    } else if typeID == CFAttributedStringGetTypeID() {
        return (value as! NSAttributedString).string
    } else if typeID == AXValueGetTypeID() {
        let axVal = value as! AXValue
        return formatAXValue(axVal, option: .default)
    } else if typeID == CFNumberGetTypeID() {
        return (value as! NSNumber).stringValue
    } else if typeID == CFBooleanGetTypeID() {
        return CFBooleanGetValue((value as! CFBoolean)) ? "true" : "false"
    } else {
        let typeDesc = CFCopyTypeIDDescription(typeID) as String? ?? "ComplexType"
        axDebugLog(
            "formatRawCFValueForTextContent: Encountered unhandled CFTypeID \(typeID) - " +
                "\(typeDesc). Returning placeholder."
        )
        return "<\(typeDesc)>"
    }
}

// formatAXValue is now defined in Values/AXValueSpecificFormatter.swift

@MainActor
internal func extractAndFormatAttribute(
    element: Element,
    attributeName: String,
    outputFormat: OutputFormat,
    valueFormatOption: ValueFormatOption,
    knownAttributes: [String: AttributeData] // Parameter is present but logic for it removed for now
) -> AnyCodable? {
    axDebugLog("extractAndFormatAttribute: '\(attributeName)' for element \(element.briefDescription(option: .short))")

    // Try to extract using known attribute handlers first
    if let extractedValue = extractKnownAttribute(element: element, attributeName: attributeName, outputFormat: outputFormat) {
        return AnyCodable(extractedValue)
    }

    // Fallback to raw attribute value
    return extractRawAttribute(element: element, attributeName: attributeName, outputFormat: outputFormat)
}

@MainActor
private func extractKnownAttribute(element: Element, attributeName: String, outputFormat: OutputFormat) -> Any? {
    switch attributeName {
    case AXAttributeNames.kAXPathHintAttribute:
        return element.attribute(Attribute<String>(AXAttributeNames.kAXPathHintAttribute))
    case AXAttributeNames.kAXRoleAttribute:
        return element.role()
    case AXAttributeNames.kAXSubroleAttribute:
        return element.subrole()
    case AXAttributeNames.kAXTitleAttribute:
        return element.title()
    case AXAttributeNames.kAXDescriptionAttribute:
        return element.descriptionText()
    case AXAttributeNames.kAXEnabledAttribute:
        return formatBooleanAttribute(element.isEnabled(), outputFormat: outputFormat)
    case AXAttributeNames.kAXFocusedAttribute:
        return formatBooleanAttribute(element.isFocused(), outputFormat: outputFormat)
    case AXAttributeNames.kAXHiddenAttribute:
        return formatBooleanAttribute(element.isHidden(), outputFormat: outputFormat)
    case AXMiscConstants.isIgnoredAttributeKey:
        let val = element.isIgnored()
        return outputFormat == .textContent ? (val ? "true" : "false") : val
    case "PID":
        return formatOptionalIntAttribute(element.pid(), outputFormat: outputFormat)
    case AXAttributeNames.kAXElementBusyAttribute:
        return formatBooleanAttribute(element.isElementBusy(), outputFormat: outputFormat)
    default:
        return nil
    }
}

@MainActor
private func formatBooleanAttribute(_ value: Bool?, outputFormat: OutputFormat) -> Any? {
    guard let val = value else { return nil }
    return outputFormat == .textContent ? val.description : val
}

@MainActor
private func formatOptionalIntAttribute(_ value: Int32?, outputFormat: OutputFormat) -> Any? {
    guard let val = value else { return nil }
    return outputFormat == .textContent ? val.description : val
}

@MainActor
private func extractRawAttribute(element: Element, attributeName: String, outputFormat: OutputFormat) -> AnyCodable? {
    let rawCFValue = element.rawAttributeValue(named: attributeName)

    if outputFormat == .textContent {
        let formatted = formatRawCFValueForTextContent(rawCFValue)
        return AnyCodable(formatted)
    }

    guard let unwrapped = ValueUnwrapper.unwrap(rawCFValue) else {
        // Only log if rawCFValue was not nil initially
        if rawCFValue != nil {
            let cfTypeID = String(describing: CFGetTypeID(rawCFValue!))
            axDebugLog(
                "extractAndFormatAttribute: '\(attributeName)' was non-nil CFTypeRef " +
                    "but unwrapped to nil. CFTypeID: \(cfTypeID)"
            )
            return AnyCodable("<Raw CFTypeRef: \(cfTypeID)>")
        }
        return nil
    }

    return AnyCodable(unwrapped)
}

@MainActor
public func getElementFullDescription(
    element: Element,
    valueFormatOption: ValueFormatOption = .default,
    includeActions: Bool = true,
    includeStoredAttributes: Bool = true,
    knownAttributes: [String: AttributeData]? = nil
) -> ([String: AnyCodable], [AXLogEntry]) {
    var attributes: [String: AnyCodable] = [:]
    axDebugLog("getElementFullDescription called for element: \(element.briefDescription(option: .short))")

    // Collect attributes in logical groups
    addBasicAttributes(to: &attributes, element: element)
    addStateAttributes(to: &attributes, element: element)
    addGeometryAttributes(to: &attributes, element: element)
    addHierarchyAttributes(to: &attributes, element: element, valueFormatOption: valueFormatOption)

    if includeActions {
        addActionAttributes(to: &attributes, element: element)
    }

    addStandardStringAttributes(to: &attributes, element: element)

    if includeStoredAttributes {
        addStoredAttributes(to: &attributes, element: element)
    }

    addComputedProperties(to: &attributes, element: element)

    axDebugLog(
        "getElementFullDescription finished for element: " +
            "\(element.briefDescription(option: .short)). Returning \(attributes.count) attributes."
    )
    return (attributes, [])
}

@MainActor
private func addBasicAttributes(to attributes: inout [String: AnyCodable], element: Element) {
    if let role = element.role() {
        attributes[AXAttributeNames.kAXRoleAttribute] = AnyCodable(role)
    }
    if let subrole = element.subrole() {
        attributes[AXAttributeNames.kAXSubroleAttribute] = AnyCodable(subrole)
    }
    if let title = element.title() {
        attributes[AXAttributeNames.kAXTitleAttribute] = AnyCodable(title)
    }
    if let descriptionText = element.descriptionText() {
        attributes[AXAttributeNames.kAXDescriptionAttribute] = AnyCodable(descriptionText)
    }
    if let value = element.value() {
        attributes[AXAttributeNames.kAXValueAttribute] = AnyCodable(value)
    }
    if let help = element.attribute(Attribute<String>(AXAttributeNames.kAXHelpAttribute)) {
        attributes[AXAttributeNames.kAXHelpAttribute] = AnyCodable(help)
    }
    if let placeholder = element.attribute(Attribute<String>(AXAttributeNames.kAXPlaceholderValueAttribute)) {
        attributes[AXAttributeNames.kAXPlaceholderValueAttribute] = AnyCodable(placeholder)
    }
}

@MainActor
private func addStateAttributes(to attributes: inout [String: AnyCodable], element: Element) {
    attributes[AXAttributeNames.kAXEnabledAttribute] = AnyCodable(element.isEnabled())
    attributes[AXAttributeNames.kAXFocusedAttribute] = AnyCodable(element.isFocused())
    attributes[AXAttributeNames.kAXHiddenAttribute] = AnyCodable(element.isHidden())
    attributes[AXMiscConstants.isIgnoredAttributeKey] = AnyCodable(element.isIgnored())
    attributes[AXAttributeNames.kAXElementBusyAttribute] = AnyCodable(element.isElementBusy())
}

@MainActor
private func addGeometryAttributes(to attributes: inout [String: AnyCodable], element: Element) {
    if let position = element.attribute(Attribute<CGPoint>(AXAttributeNames.kAXPositionAttribute)) {
        attributes[AXAttributeNames.kAXPositionAttribute] = AnyCodable(NSPointToDictionary(position))
    }
    if let size = element.attribute(Attribute<CGSize>(AXAttributeNames.kAXSizeAttribute)) {
        attributes[AXAttributeNames.kAXSizeAttribute] = AnyCodable(NSSizeToDictionary(size))
    }
}

@MainActor
private func addHierarchyAttributes(to attributes: inout [String: AnyCodable], element: Element, valueFormatOption: ValueFormatOption) {
    if let parent = element.parent() {
        attributes[AXAttributeNames.kAXParentAttribute] = AnyCodable(
            parent.briefDescription(option: valueFormatOption)
        )
    }
    if let children = element.children() {
        attributes[AXAttributeNames.kAXChildrenAttribute] = AnyCodable(
            children.map { $0.briefDescription(option: valueFormatOption) }
        )
    }
}

@MainActor
private func addActionAttributes(to attributes: inout [String: AnyCodable], element: Element) {
    var actionsToStore: [String]?

    if let currentActions = element.supportedActions(), !currentActions.isEmpty {
        actionsToStore = currentActions
    } else if let fallbackActions: [String] = element.attribute(
        Attribute<[String]>(AXAttributeNames.kAXActionsAttribute)
    ), !fallbackActions.isEmpty {
        actionsToStore = fallbackActions
        axDebugLog("Used fallback kAXActionsAttribute for \(element.briefDescription(option: .short))")
    }

    attributes[AXAttributeNames.kAXActionsAttribute] = actionsToStore != nil
        ? AnyCodable(actionsToStore)
        : AnyCodable(nil as [String]?)

    if element.isActionSupported(AXActionNames.kAXPressAction) {
        attributes["\(AXActionNames.kAXPressAction)_Supported"] = AnyCodable(true)
    }
}

@MainActor
private func addStandardStringAttributes(to attributes: inout [String: AnyCodable], element: Element) {
    let standardAttributes = [
        AXAttributeNames.kAXRoleDescriptionAttribute,
        AXAttributeNames.kAXValueDescriptionAttribute,
        AXAttributeNames.kAXIdentifierAttribute
    ]

    for attrName in standardAttributes {
        if attributes[attrName] == nil,
           let attrValue: String = element.attribute(Attribute<String>(attrName)) {
            attributes[attrName] = AnyCodable(attrValue)
        }
    }
}

@MainActor
private func addStoredAttributes(to attributes: inout [String: AnyCodable], element: Element) {
    guard let stored = element.attributes else { return }

    for (key, val) in stored where attributes[key] == nil {
        attributes[key] = val
    }
}

@MainActor
private func addComputedProperties(to attributes: inout [String: AnyCodable], element: Element) {
    if attributes[AXMiscConstants.computedNameAttributeKey] == nil,
       let name = element.computedName() {
        attributes[AXMiscConstants.computedNameAttributeKey] = AnyCodable(name)
    }

    if attributes[AXMiscConstants.computedPathAttributeKey] == nil {
        attributes[AXMiscConstants.computedPathAttributeKey] = AnyCodable(element.generatePathString())
    }

    if attributes[AXMiscConstants.isClickableAttributeKey] == nil {
        let isButton = element.role() == AXRoleNames.kAXButtonRole
        let hasPressAction = element.isActionSupported(AXActionNames.kAXPressAction)
        if isButton || hasPressAction {
            attributes[AXMiscConstants.isClickableAttributeKey] = AnyCodable(true)
        }
    }
}

@MainActor
private func formatParentAttribute(
    _ parent: Element?,
    outputFormat: OutputFormat,
    valueFormatOption: ValueFormatOption
) -> AnyCodable? {
    guard let parentElement = parent else { return nil }
    if outputFormat == .textContent {
        return AnyCodable(parentElement.briefDescription(option: .short))
    }
    return AnyCodable(parentElement.briefDescription(option: valueFormatOption))
}

@MainActor
private func formatChildrenAttribute(
    _ children: [Element]?,
    outputFormat: OutputFormat,
    valueFormatOption: ValueFormatOption
) -> AnyCodable? {
    guard let childElements = children else { return nil }
    if outputFormat == .textContent {
        return AnyCodable(
            childElements.map { $0.briefDescription(option: .short) }.joined(separator: ", ")
        )
    }
    return AnyCodable(childElements.map { $0.briefDescription(option: valueFormatOption) })
}

@MainActor
private func formatFocusedUIElementAttribute(
    _ focusedElement: Element?,
    outputFormat: OutputFormat,
    valueFormatOption: ValueFormatOption
) -> AnyCodable? {
    guard let focusedElem = focusedElement else { return nil }
    if outputFormat == .textContent {
        return AnyCodable(focusedElem.briefDescription(option: .short))
    }
    return AnyCodable(focusedElem.briefDescription(option: valueFormatOption))
}

// formatValue is likely not needed anymore if ValueUnwrapper is robust and
// extractAndFormatAttribute handles types correctly.
// Keeping it commented out for now, can be removed if confirmed.
/*
 @MainActor
 func formatValue(_ value: Any?, outputFormat: OutputFormat, valueFormatOption: ValueFormatOption) -> AnyCodable? {
     guard let val = value else { return nil }

     if outputFormat == .textContent {
         if let strVal = val as? String { return AnyCodable(strVal) }
         if let attrStrVal = val as? NSAttributedString { return AnyCodable(attrStrVal.string) }
         if let boolVal = val as? Bool { return AnyCodable(boolVal.description) }
         if let numVal = val as? NSNumber { return AnyCodable(numVal.stringValue) }
         // For other complex types, a generic description
         return AnyCodable("<".appending(String(describing: type(of: val))).appending(">"))
     }

     // For JSON or other structured output, try to preserve type or use AnyCodable
     if let axVal = val as? AXValue { // AXValue might not be directly Codable
         return AnyCodable(formatAXValue(axVal, option: valueFormatOption))
     } else if let elementVal = val as? Element { // Element might not be directly Codable in all contexts
         return AnyCodable(elementVal.briefDescription(option: valueFormatOption))
     } else if let arrayVal = val as? [Any?] {
         return AnyCodable(
             arrayVal.map {
                 formatValue($0, outputFormat: outputFormat, valueFormatOption: valueFormatOption)?.value
             }
         ) // Recursively format
     } else if let dictVal = val as? [String: Any?] {
         return AnyCodable(
             dictVal.mapValues {
                 formatValue($0, outputFormat: outputFormat, valueFormatOption: valueFormatOption)?.value
             }
         )
     }

     return AnyCodable(val) // Fallback to AnyCodable directly
 }
 */
