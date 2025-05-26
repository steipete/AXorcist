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
        if requestedAttributes == nil || requestedAttributes!.isEmpty {
            // If no specific attributes are requested, decide what to do based on context
            // This part of the logic for deciding what to fetch if nothing specific is requested
            // has been simplified or might be intended to be expanded.
            // For now, if forMultiDefault is true, it implies fetching a default set (e.g., for multi-element views)
            // otherwise, it might fetch all or a basic set.
            // This example assumes if not forMultiDefault, and no specifics, it fetches all available.
            if !forMultiDefault {
                // Example: Fetch all attribute names if none are specified and not for a multi-default scenario
                if let names = element.attributeNames() {
                    attributesToFetch.append(contentsOf: names)
                    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "determineAttributesToFetch: No specific attributes requested, fetched all \(names.count) available: \(names.joined(separator: ", "))"))
                } else {
                    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message:
                        "determineAttributesToFetch: No specific attributes requested and " +
                            "failed to fetch all available names."
                    ))
                }
            } else {
                // For multi-default, or if the above block doesn't execute,
                // it might rely on a predefined default set or do nothing further here,
                // letting subsequent logic handle AXorcist.defaultAttributesToFetch if attributesToFetch remains empty.
                 GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message:
                    "determineAttributesToFetch: No specific attributes requested. Using defaults or context-specific set."
                ))
            }
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
    valueFormatOption: ValueFormatOption = .smart
) async -> ([String: AnyCodable], [AXLogEntry]) {
    var result: [String: AnyCodable] = [:]

    let requestingStr = attrNames.isEmpty ? "all" : attrNames.joined(separator: ", ")
    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: 
        "getElementAttributes called for element: \(element.briefDescription(option: .raw)), " +
        "requesting: \(requestingStr)"
    ))

    let attributesToProcess = attrNames.isEmpty ? (element.attributeNames() ?? []) : attrNames

    for attr in attributesToProcess {
        if attr == AXAttributeNames.kAXParentAttribute {
            let parent = element.parent()
            result[AXAttributeNames.kAXParentAttribute] = await formatParentAttribute(
                parent,
                outputFormat: outputFormat,
                valueFormatOption: valueFormatOption
            )
        } else if attr == AXAttributeNames.kAXChildrenAttribute {
            let children = element.children()
            result[attr] = await formatChildrenAttribute(
                children,
                outputFormat: outputFormat,
                valueFormatOption: valueFormatOption
            )
        } else if attr == AXAttributeNames.kAXFocusedUIElementAttribute {
            let focused = element.focusedUIElement()
            result[attr] = await formatFocusedUIElementAttribute(
                focused,
                outputFormat: outputFormat,
                valueFormatOption: valueFormatOption
            )
        } else {
            result[attr] = await extractAndFormatAttribute(
                element: element,
                attributeName: attr,
                outputFormat: outputFormat,
                valueFormatOption: valueFormatOption
            )
        }
    }

    if outputFormat == .verbose && result[AXMiscConstants.computedPathAttributeKey] == nil {
        let path = element.generatePathString()
        result[AXMiscConstants.computedPathAttributeKey] = AnyCodable(path)
    }

    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: 
        "getElementAttributes finished for element: \(element.briefDescription(option: .raw)). " +
        "Returning \(result.count) attributes."
    ))
    return (result, [])
}

@MainActor
public func getAllElementDataForAXpector(
    for element: Element,
    outputFormat: OutputFormat = .jsonString, // Typically .jsonString for AXpector
    valueFormatOption: ValueFormatOption = .smart
) async -> ([String: AnyCodable], ElementDetails) {

    var attributes: [String: AnyCodable] = [:]
    var elementDetails = ElementDetails()

    let allAttributeNames = element.attributeNames() ?? []
    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message:
        "getAllElementDataForAXpector: Fetching \(allAttributeNames.count) attributes for " +
            "\(element.briefDescription(option: .raw))."
    ))

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
    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "getAllElementDataForAXpector: Finished processing for \(element.briefDescription(option: .raw))."))
    return (attributes, elementDetails)
}

// Function to get specifically computed attributes for an element
@MainActor
internal func getComputedAttributes(for element: Element) async -> [String: AttributeData] {
    var computedAttrs: [String: AttributeData] = [:]

    if let name = element.computedName() {
        computedAttrs[AXMiscConstants.computedNameAttributeKey] = AttributeData(
            value: AnyCodable(name),
            source: .computed
        )
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message:
            "getComputedAttributes: Computed name for element " +
                "\(element.briefDescription(option: .raw)) is '\(name)'."
        ))
    } else {
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message:
            "getComputedAttributes: Element \(element.briefDescription(option: .raw)) " +
                "has no computed name."
        ))
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
internal func formatRawCFValueForTextContent(_ rawValue: CFTypeRef?) async -> String {
    guard let value = rawValue else { return AXMiscConstants.kAXNotAvailableString }
    let typeID = CFGetTypeID(value)
    if typeID == CFStringGetTypeID() {
        return (value as! String)
    } else if typeID == CFAttributedStringGetTypeID() {
        return (value as! NSAttributedString).string
    } else if typeID == AXValueGetTypeID() {
        let axVal = value as! AXValue
        return formatAXValue(axVal, option: ValueFormatOption.smart)
    } else if typeID == CFNumberGetTypeID() {
        return (value as! NSNumber).stringValue
    } else if typeID == CFBooleanGetTypeID() {
        return CFBooleanGetValue((value as! CFBoolean)) ? "true" : "false"
    } else {
        let typeDesc = CFCopyTypeIDDescription(typeID) as String? ?? "ComplexType"
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message:
            "formatRawCFValueForTextContent: Encountered unhandled CFTypeID \(typeID) - " +
                "\(typeDesc). Returning placeholder."
        ))
        return "<\(typeDesc)>"
    }
}

// formatAXValue is now defined in Values/AXValueSpecificFormatter.swift

@MainActor
internal func extractAndFormatAttribute(
    element: Element,
    attributeName: String,
    outputFormat: OutputFormat,
    valueFormatOption: ValueFormatOption
) async -> AnyCodable? {
    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "extractAndFormatAttribute: '\(attributeName)' for element \(element.briefDescription(option: .raw))"))

    // Try to extract using known attribute handlers first
    if let extractedValue = await extractKnownAttribute(element: element, attributeName: attributeName, outputFormat: outputFormat) {
        return AnyCodable(extractedValue)
    }

    // Fallback to raw attribute value
    return await extractRawAttribute(element: element, attributeName: attributeName, outputFormat: outputFormat)
}

@MainActor
private func extractKnownAttribute(element: Element, attributeName: String, outputFormat: OutputFormat) async -> Any? {
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
private func extractRawAttribute(element: Element, attributeName: String, outputFormat: OutputFormat) async -> AnyCodable? {
    let rawCFValue = element.rawAttributeValue(named: attributeName)

    if outputFormat == .textContent {
        let formatted = await formatRawCFValueForTextContent(rawCFValue)
        return AnyCodable(formatted)
    }

    guard let unwrapped = ValueUnwrapper.unwrap(rawCFValue) else {
        // Only log if rawCFValue was not nil initially
        if rawCFValue != nil {
            let cfTypeID = String(describing: CFGetTypeID(rawCFValue!))
            GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message:
                "extractAndFormatAttribute: '\(attributeName)' was non-nil CFTypeRef " +
                    "but unwrapped to nil. CFTypeID: \(cfTypeID)"
            ))
            return AnyCodable("<Raw CFTypeRef: \(cfTypeID)>")
        }
        return nil
    }

    return AnyCodable(unwrapped)
}

@MainActor
public func getElementFullDescription(
    element: Element,
    valueFormatOption: ValueFormatOption = .smart,
    includeActions: Bool = true,
    includeStoredAttributes: Bool = true,
    knownAttributes: [String: AttributeData]? = nil
) async -> ([String: AnyCodable], [AXLogEntry]) {
    var attributes: [String: AnyCodable] = [:]
    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "getElementFullDescription called for element: \(element.briefDescription(option: .raw))"))

    // Collect attributes in logical groups
    await addBasicAttributes(to: &attributes, element: element)
    await addStateAttributes(to: &attributes, element: element)
    await addGeometryAttributes(to: &attributes, element: element)
    await addHierarchyAttributes(to: &attributes, element: element, valueFormatOption: valueFormatOption)

    if includeActions {
        await addActionAttributes(to: &attributes, element: element)
    }

    await addStandardStringAttributes(to: &attributes, element: element)

    if includeStoredAttributes {
        addStoredAttributes(to: &attributes, element: element)
    }

    await addComputedProperties(to: &attributes, element: element)

    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message:
        "getElementFullDescription finished for element: " +
            "\(element.briefDescription(option: .raw)). Returning \(attributes.count) attributes."
    ))
    return (attributes, [])
}

@MainActor
private func addBasicAttributes(to attributes: inout [String: AnyCodable], element: Element) async {
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
private func addStateAttributes(to attributes: inout [String: AnyCodable], element: Element) async {
    attributes[AXAttributeNames.kAXEnabledAttribute] = AnyCodable(element.isEnabled())
    attributes[AXAttributeNames.kAXFocusedAttribute] = AnyCodable(element.isFocused())
    attributes[AXAttributeNames.kAXHiddenAttribute] = AnyCodable(element.isHidden())
    attributes[AXMiscConstants.isIgnoredAttributeKey] = AnyCodable(element.isIgnored())
    attributes[AXAttributeNames.kAXElementBusyAttribute] = AnyCodable(element.isElementBusy())
}

@MainActor
private func addGeometryAttributes(to attributes: inout [String: AnyCodable], element: Element) async {
    if let position = element.attribute(Attribute<CGPoint>(AXAttributeNames.kAXPositionAttribute)) {
        attributes[AXAttributeNames.kAXPositionAttribute] = AnyCodable(NSPointToDictionary(position))
    }
    if let size = element.attribute(Attribute<CGSize>(AXAttributeNames.kAXSizeAttribute)) {
        attributes[AXAttributeNames.kAXSizeAttribute] = AnyCodable(NSSizeToDictionary(size))
    }
}

@MainActor
private func addHierarchyAttributes(to attributes: inout [String: AnyCodable], element: Element, valueFormatOption: ValueFormatOption) async {
    if let parent = element.parent() {
        attributes[AXAttributeNames.kAXParentAttribute] = AnyCodable(
            parent.briefDescription(option: .raw)
        )
    }
    if let children = element.children() {
        attributes[AXAttributeNames.kAXChildrenAttribute] = AnyCodable(
            children.map { $0.briefDescription(option: .raw) }
        )
    }
}

@MainActor
private func addActionAttributes(to attributes: inout [String: AnyCodable], element: Element) async {
    var actionsToStore: [String]?

    if let currentActions = element.supportedActions(), !currentActions.isEmpty {
        actionsToStore = currentActions
    } else if let fallbackActions: [String] = element.attribute(
        Attribute<[String]>(AXAttributeNames.kAXActionsAttribute)
    ), !fallbackActions.isEmpty {
        actionsToStore = fallbackActions
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "Used fallback kAXActionsAttribute for \(element.briefDescription(option: .raw))"))
    }

    attributes[AXAttributeNames.kAXActionsAttribute] = actionsToStore != nil
        ? AnyCodable(actionsToStore)
        : AnyCodable(nil as [String]?)

    if element.isActionSupported(AXActionNames.kAXPressAction) {
        attributes["\(AXActionNames.kAXPressAction)_Supported"] = AnyCodable(true)
    }
}

@MainActor
private func addStandardStringAttributes(to attributes: inout [String: AnyCodable], element: Element) async {
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
private func addComputedProperties(to attributes: inout [String: AnyCodable], element: Element) async {
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
) async -> AnyCodable {
    guard let parentElement = parent else { return AnyCodable(nil as String?) }
    if outputFormat == .textContent {
        return AnyCodable("Element: \(parentElement.role() ?? "?Role")")
    } else {
        return AnyCodable(parentElement.briefDescription(option: .raw))
    }
}

@MainActor
private func formatChildrenAttribute(
    _ children: [Element]?,
    outputFormat: OutputFormat,
    valueFormatOption: ValueFormatOption
) async -> AnyCodable {
    guard let actualChildren = children, !actualChildren.isEmpty else {
        return AnyCodable(nil as String?)
    }
    if outputFormat == .textContent {
        var childrenSummaries: [String] = []
        for childElement in actualChildren {
            childrenSummaries.append(childElement.briefDescription(option: .raw))
        }
        return AnyCodable("[\(childrenSummaries.joined(separator: ", "))]")
    } else {
        let childrenDescriptions = actualChildren.map { $0.briefDescription(option: .raw) }
        return AnyCodable(childrenDescriptions)
    }
}

@MainActor
private func formatFocusedUIElementAttribute(
    _ focusedElement: Element?,
    outputFormat: OutputFormat,
    valueFormatOption: ValueFormatOption
) async -> AnyCodable {
    guard let element = focusedElement else { return AnyCodable(nil as String?) }
    if outputFormat == .textContent {
        return AnyCodable("Focused: \(element.role() ?? "?Role") - \(element.title() ?? "?Title")")
    } else {
        return AnyCodable(element.briefDescription(option: .raw))
    }
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
