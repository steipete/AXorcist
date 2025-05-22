import ApplicationServices
import Foundation

// MARK: - Element Hierarchy Logic

extension Element {
    @MainActor
    public func children(isDebugLoggingEnabled: Bool, currentDebugLogs: inout [String]) -> [Element]? {
        func dLog(_ message: String) { if isDebugLoggingEnabled { currentDebugLogs.append(AXorcist.formatDebugLogMessage(message, applicationName: nil, commandID: nil, file: #file, function: #function, line: #line)) } }

        let elementDescription = self.briefDescription(
            option: .default,
            isDebugLoggingEnabled: isDebugLoggingEnabled,
            currentDebugLogs: &currentDebugLogs
        )
        dLog("Getting children for element: \(elementDescription)")

        var childCollector = ChildCollector()

        // Collect children from various sources
        collectDirectChildren(
            collector: &childCollector,
            isDebugLoggingEnabled: isDebugLoggingEnabled,
            currentDebugLogs: &currentDebugLogs
        )

        collectAlternativeChildren(
            collector: &childCollector,
            isDebugLoggingEnabled: isDebugLoggingEnabled,
            currentDebugLogs: &currentDebugLogs
        )

        collectApplicationWindows(
            collector: &childCollector,
            isDebugLoggingEnabled: isDebugLoggingEnabled,
            currentDebugLogs: &currentDebugLogs
        )

        let result = childCollector.finalizeResults(dLog: dLog)
        dLog("Final children count from Element.children: \(result?.count ?? 0)")
        return result
    }

    @MainActor
    private func collectDirectChildren(
        collector: inout ChildCollector,
        isDebugLoggingEnabled: Bool,
        currentDebugLogs: inout [String]
    ) {
        // DO NOT CALL self.briefDescription() or self.attribute() BEFORE THE kAXChildrenAttribute CALL BELOW
        // Log entry for this function can be done by the caller (Element.children) if needed before this is called,
        // or log a generic message here without using self.briefDescription().
        currentDebugLogs.append(AXorcist.formatDebugLogMessage("collectDirectChildren: Attempting to fetch kAXChildrenAttribute directly.", applicationName: nil, commandID: nil, file: #file, function: #function, line: #line))

        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(self.underlyingElement, kAXChildrenAttribute as CFString, &value)

        // It's safer to get description AFTER the critical kAXChildrenAttribute call
        let selfDescForLog = isDebugLoggingEnabled ? self.briefDescription(option: .short, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &currentDebugLogs) : "Element(debug_off)"

        if error == .success {
            if let childrenCFArray = value, CFGetTypeID(childrenCFArray) == CFArrayGetTypeID() {
                if let directChildrenUI = childrenCFArray as? [AXUIElement] {
                    currentDebugLogs.append(AXorcist.formatDebugLogMessage("collectDirectChildren [\(selfDescForLog)]: Successfully fetched and cast \(directChildrenUI.count) direct children.", applicationName: nil, commandID: nil, file: #file, function: #function, line: #line))
                    collector.addChildren(from: directChildrenUI)
                } else {
                    currentDebugLogs.append(AXorcist.formatDebugLogMessage("collectDirectChildren [\(selfDescForLog)]: kAXChildrenAttribute was a CFArray but failed to cast to [AXUIElement]. TypeID: \(CFGetTypeID(childrenCFArray))", applicationName: nil, commandID: nil, file: #file, function: #function, line: #line))
                }
            } else if let nonArrayValue = value { 
                currentDebugLogs.append(AXorcist.formatDebugLogMessage("collectDirectChildren [\(selfDescForLog)]: kAXChildrenAttribute was not a CFArray. TypeID: \(CFGetTypeID(nonArrayValue)). Value: \(String(describing: nonArrayValue))", applicationName: nil, commandID: nil, file: #file, function: #function, line: #line))
            } else {
                currentDebugLogs.append(AXorcist.formatDebugLogMessage("collectDirectChildren [\(selfDescForLog)]: kAXChildrenAttribute was nil despite .success error code.", applicationName: nil, commandID: nil, file: #file, function: #function, line: #line))
            }
        } else if error == .noValue {
             currentDebugLogs.append(AXorcist.formatDebugLogMessage("collectDirectChildren [\(selfDescForLog)]: kAXChildrenAttribute has no value.", applicationName: nil, commandID: nil, file: #file, function: #function, line: #line))
        } else {
            currentDebugLogs.append(AXorcist.formatDebugLogMessage("collectDirectChildren [\(selfDescForLog)]: Error fetching kAXChildrenAttribute: \(error.rawValue)", applicationName: nil, commandID: nil, file: #file, function: #function, line: #line))
        }
        // No CFRelease(value) needed here if childrenCFArray was an array, as `as? [AXUIElement]` handles bridging.
        // If it was nonArrayValue, it's a bit more ambiguous but usually these are also bridged or not needing manual release for simple gets.
    }

    @MainActor
    private func collectAlternativeChildren(
        collector: inout ChildCollector,
        isDebugLoggingEnabled: Bool,
        currentDebugLogs: inout [String]
    ) {
        let alternativeAttributes: [String] = [
            kAXVisibleChildrenAttribute, kAXWebAreaChildrenAttribute, kAXHTMLContentAttribute,
            kAXARIADOMChildrenAttribute, kAXDOMChildrenAttribute, kAXApplicationNavigationAttribute,
            kAXApplicationElementsAttribute, kAXContentsAttribute, kAXBodyAreaAttribute, kAXDocumentContentAttribute,
            kAXWebPageContentAttribute, kAXSplitGroupContentsAttribute, kAXLayoutAreaChildrenAttribute,
            kAXGroupChildrenAttribute, kAXSelectedChildrenAttribute, kAXRowsAttribute, kAXColumnsAttribute,
            kAXTabsAttribute
        ]
        currentDebugLogs.append(AXorcist.formatDebugLogMessage("collectAlternativeChildren: Will iterate \(alternativeAttributes.count) alternative attributes.", applicationName: nil, commandID: nil, file: #file, function: #function, line: #line))

        for attrName in alternativeAttributes {
            collectChildrenFromAttribute(
                attributeName: attrName,
                collector: &collector,
                isDebugLoggingEnabled: isDebugLoggingEnabled,
                currentDebugLogs: &currentDebugLogs
            )
        }
    }

    @MainActor
    private func collectChildrenFromAttribute(
        attributeName: String,
        collector: inout ChildCollector,
        isDebugLoggingEnabled: Bool,
        currentDebugLogs: inout [String]
    ) {
        var tempLogs: [String] = []
        currentDebugLogs.append(AXorcist.formatDebugLogMessage("collectChildrenFromAttribute: Trying '\(attributeName)'.", applicationName: nil, commandID: nil, file: #file, function: #function, line: #line))

        if let childrenUI: [AXUIElement] = attribute(
            Attribute<[AXUIElement]>(attributeName),
            isDebugLoggingEnabled: isDebugLoggingEnabled,
            currentDebugLogs: &tempLogs
        ) {
            currentDebugLogs.append(contentsOf: tempLogs)
            if !childrenUI.isEmpty {
                currentDebugLogs.append(AXorcist.formatDebugLogMessage("collectChildrenFromAttribute: Successfully fetched \(childrenUI.count) children from '\(attributeName)'.", applicationName: nil, commandID: nil, file: #file, function: #function, line: #line))
                collector.addChildren(from: childrenUI)
            } else {
                 currentDebugLogs.append(AXorcist.formatDebugLogMessage("collectChildrenFromAttribute: Fetched EMPTY array from '\(attributeName)'.", applicationName: nil, commandID: nil, file: #file, function: #function, line: #line))
            }
        } else {
            currentDebugLogs.append(contentsOf: tempLogs)
            currentDebugLogs.append(AXorcist.formatDebugLogMessage("collectChildrenFromAttribute: Attribute '\(attributeName)' returned nil or was not [AXUIElement].", applicationName: nil, commandID: nil, file: #file, function: #function, line: #line))
        }
    }

    @MainActor
    private func collectApplicationWindows(
        collector: inout ChildCollector,
        isDebugLoggingEnabled: Bool,
        currentDebugLogs: inout [String]
    ) {
        var tempLogsForRole: [String] = []
        let currentRole = self.role(isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &tempLogsForRole)
        currentDebugLogs.append(contentsOf: tempLogsForRole)

        if currentRole == kAXApplicationRole as String {
            currentDebugLogs.append(AXorcist.formatDebugLogMessage("collectApplicationWindows: Element is AXApplication. Trying kAXWindowsAttribute.", applicationName: nil, commandID: nil, file: #file, function: #function, line: #line))
            var tempLogsForWindows: [String] = []
            if let windowElementsUI: [AXUIElement] = attribute(
                Attribute<[AXUIElement]>.windows,
                isDebugLoggingEnabled: isDebugLoggingEnabled,
                currentDebugLogs: &tempLogsForWindows
            ) {
                currentDebugLogs.append(contentsOf: tempLogsForWindows)
                if !windowElementsUI.isEmpty {
                    currentDebugLogs.append(AXorcist.formatDebugLogMessage("collectApplicationWindows: Successfully fetched \(windowElementsUI.count) windows.", applicationName: nil, commandID: nil, file: #file, function: #function, line: #line))
                    collector.addChildren(from: windowElementsUI)
                } else {
                    currentDebugLogs.append(AXorcist.formatDebugLogMessage("collectApplicationWindows: Fetched EMPTY array from kAXWindowsAttribute.", applicationName: nil, commandID: nil, file: #file, function: #function, line: #line))
                }
            } else {
                currentDebugLogs.append(contentsOf: tempLogsForWindows)
                currentDebugLogs.append(AXorcist.formatDebugLogMessage("collectApplicationWindows: Attribute kAXWindowsAttribute returned nil.", applicationName: nil, commandID: nil, file: #file, function: #function, line: #line))
            }
        }
    }

    // generatePathString() is now fully implemented in Element.swift
}

// MARK: - Child Collection Helper

private struct ChildCollector {
    private var collectedChildren: [Element] = []
    private var uniqueChildrenSet = Set<Element>()

    mutating func addChildren(from childrenUI: [AXUIElement]) {
        for childUI in childrenUI {
            let childElement = Element(childUI)
            if !uniqueChildrenSet.contains(childElement) {
                // Log before adding
                // AXorcist.formatDebugLogMessage("ChildCollector: Adding new child: \(childElement.briefDescription(option: .minimal))", ... ) - too verbose for now
                collectedChildren.append(childElement)
                uniqueChildrenSet.insert(childElement)
            }
        }
    }

    func finalizeResults(dLog: (String) -> Void) -> [Element]? {
        if collectedChildren.isEmpty {
            dLog("ChildCollector.finalizeResults: No children found for element after all collection methods.")
            return nil
        } else {
            dLog("ChildCollector.finalizeResults: Found \(collectedChildren.count) unique children after all collection methods.")
            return collectedChildren
        }
    }
}
