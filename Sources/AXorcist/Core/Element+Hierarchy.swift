import ApplicationServices
import Foundation
// GlobalAXLogger should be available

// MARK: - Element Hierarchy Logic

extension Element {
    @MainActor
    public func children(strict: Bool = false) -> [Element]? { // Added strict parameter
        // Logging for this top-level call
        // self.briefDescription() is assumed to be refactored and available
        axDebugLog("Getting children for element: \(self.briefDescription(option: .default)), strict: \(strict)")

        var childCollector = ChildCollector() // ChildCollector will use GlobalAXLogger internally

        collectDirectChildren(collector: &childCollector)
        
        if !strict { // Only collect alternatives if not strict
            collectAlternativeChildren(collector: &childCollector)
            collectApplicationWindows(collector: &childCollector)
        }

        let result = childCollector.finalizeResults()
        axDebugLog("Final children count: \(result?.count ?? 0)")
        return result
    }

    @MainActor
    private func collectDirectChildren(collector: inout ChildCollector) {
        axDebugLog("Attempting to fetch kAXChildrenAttribute directly.")

        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(
            self.underlyingElement,
            AXAttributeNames.kAXChildrenAttribute as CFString,
            &value
        )

        // self.briefDescription() is assumed to be refactored
        let selfDescForLog = self.briefDescription(option: .short)

        if error == .success {
            if let childrenCFArray = value, CFGetTypeID(childrenCFArray) == CFArrayGetTypeID() {
                if let directChildrenUI = childrenCFArray as? [AXUIElement] {
                    axDebugLog(
                        "[\(selfDescForLog)]: Successfully fetched and cast " +
                        "\(directChildrenUI.count) direct children."
                    )
                    collector.addChildren(from: directChildrenUI)
                } else {
                    axDebugLog(
                        "[\(selfDescForLog)]: kAXChildrenAttribute was a CFArray but failed to cast " +
                        "to [AXUIElement]. TypeID: \(CFGetTypeID(childrenCFArray))"
                    )
                }
            } else if let nonArrayValue = value {
                axDebugLog(
                    "[\(selfDescForLog)]: kAXChildrenAttribute was not a CFArray. " +
                    "TypeID: \(CFGetTypeID(nonArrayValue)). Value: \(String(describing: nonArrayValue))"
                )
            } else {
                axDebugLog("[\(selfDescForLog)]: kAXChildrenAttribute was nil despite .success error code.")
            }
        } else if error == .noValue {
            axDebugLog("[\(selfDescForLog)]: kAXChildrenAttribute has no value.")
        } else {
            axDebugLog("[\(selfDescForLog)]: Error fetching kAXChildrenAttribute: \(error.rawValue)")
        }
    }

    @MainActor
    private func collectAlternativeChildren(collector: inout ChildCollector) {
        let alternativeAttributes: [String] = [
            AXAttributeNames.kAXVisibleChildrenAttribute, AXAttributeNames.kAXWebAreaChildrenAttribute,
            AXAttributeNames.kAXApplicationNavigationAttribute, AXAttributeNames.kAXApplicationElementsAttribute,
            AXAttributeNames.kAXBodyAreaAttribute, AXAttributeNames.kAXSplitGroupContentsAttribute,
            AXAttributeNames.kAXLayoutAreaChildrenAttribute, AXAttributeNames.kAXGroupChildrenAttribute,
            AXAttributeNames.kAXSelectedChildrenAttribute, AXAttributeNames.kAXRowsAttribute,
            AXAttributeNames.kAXColumnsAttribute, AXAttributeNames.kAXTabsAttribute
        ]
        axDebugLog(
            "Using pruned attribute list (\(alternativeAttributes.count) items) " +
            "to avoid heavy payloads for alternative children."
        )

        for attrName in alternativeAttributes {
            collectChildrenFromAttribute(attributeName: attrName, collector: &collector)
        }
    }

    @MainActor
    private func collectChildrenFromAttribute(attributeName: String, collector: inout ChildCollector) {
        axDebugLog("Trying alternative child attribute: '\(attributeName)'.")
        // self.attribute() now uses GlobalAXLogger and returns T?
        if let childrenUI: [AXUIElement] = attribute(Attribute(attributeName)) {
            if !childrenUI.isEmpty {
                axDebugLog("Successfully fetched \(childrenUI.count) children from '\(attributeName)'.")
                collector.addChildren(from: childrenUI)
            } else {
                axDebugLog("Fetched EMPTY array from '\(attributeName)'.")
            }
        } else {
            // attribute() logs its own failures/nil results
            axDebugLog("Attribute '\(attributeName)' returned nil or was not [AXUIElement].")
        }
    }

    @MainActor
    private func collectApplicationWindows(collector: inout ChildCollector) {
        // self.role() now uses GlobalAXLogger and is assumed refactored
        if self.role() == AXRoleNames.kAXApplicationRole {
            axDebugLog("Element is AXApplication. Trying kAXWindowsAttribute.")
            // self.attribute() for .windows, assumed refactored
            if let windowElementsUI: [AXUIElement] = attribute(.windows) {
                if !windowElementsUI.isEmpty {
                    axDebugLog("Successfully fetched \(windowElementsUI.count) windows.")
                    collector.addChildren(from: windowElementsUI)
                } else {
                    axDebugLog("Fetched EMPTY array from kAXWindowsAttribute.")
                }
            } else {
                axDebugLog("Attribute kAXWindowsAttribute returned nil for Application element.")
            }
        }
    }
}

// MARK: - Child Collection Helper
private let maxChildrenPerElement = 500

private struct ChildCollector {
    private var collectedChildren: [Element] = []
    private var uniqueChildrenSet = Set<Element>()
    private var limitReached = false

    mutating func addChildren(from childrenUI: [AXUIElement]) { // Removed dLog param
        if limitReached { return }

        for childUI in childrenUI {
            if collectedChildren.count >= maxChildrenPerElement {
                if !limitReached {
                    axWarningLog(
                        "ChildCollector: Reached maximum children limit (\(maxChildrenPerElement)). " +
                        "No more children will be added for this element."
                    )
                    limitReached = true
                }
                break
            }

            let childElement = Element(childUI)
            if !uniqueChildrenSet.contains(childElement) {
                collectedChildren.append(childElement)
                uniqueChildrenSet.insert(childElement)
            }
        }
    }

    func finalizeResults() -> [Element]? { // Removed dLog param
        if collectedChildren.isEmpty {
            axDebugLog("ChildCollector: No children found after all collection methods.")
            return nil
        } else {
            axDebugLog("ChildCollector: Found \(collectedChildren.count) unique children.")
            return collectedChildren
        }
    }
}
