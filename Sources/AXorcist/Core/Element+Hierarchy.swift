import ApplicationServices
import Foundation

// MARK: - Element Hierarchy Logic

extension Element {
    @MainActor
    public func children(isDebugLoggingEnabled: Bool, currentDebugLogs: inout [String]) -> [Element]? {
        func dLog(_ message: String) { if isDebugLoggingEnabled { currentDebugLogs.append(message) } }

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

        return childCollector.finalizeResults(dLog: dLog)
    }

    @MainActor
    private func collectDirectChildren(
        collector: inout ChildCollector,
        isDebugLoggingEnabled: Bool,
        currentDebugLogs: inout [String]
    ) {
        var tempLogs: [String] = []

        if let directChildrenUI: [AXUIElement] = attribute(
            Attribute<[AXUIElement]>.children,
            isDebugLoggingEnabled: isDebugLoggingEnabled,
            currentDebugLogs: &tempLogs
        ) {
            currentDebugLogs.append(contentsOf: tempLogs)
            collector.addChildren(from: directChildrenUI)
        } else {
            currentDebugLogs.append(contentsOf: tempLogs)
        }
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

        if let childrenUI: [AXUIElement] = attribute(
            Attribute<[AXUIElement]>(attributeName),
            isDebugLoggingEnabled: isDebugLoggingEnabled,
            currentDebugLogs: &tempLogs
        ) {
            currentDebugLogs.append(contentsOf: tempLogs)
            collector.addChildren(from: childrenUI)
        } else {
            currentDebugLogs.append(contentsOf: tempLogs)
        }
    }

    @MainActor
    private func collectApplicationWindows(
        collector: inout ChildCollector,
        isDebugLoggingEnabled: Bool,
        currentDebugLogs: inout [String]
    ) {
        var tempLogs: [String] = []
        let currentRole = self.role(isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &tempLogs)
        currentDebugLogs.append(contentsOf: tempLogs)

        if currentRole == kAXApplicationRole as String {
            tempLogs.removeAll()
            if let windowElementsUI: [AXUIElement] = attribute(
                Attribute<[AXUIElement]>.windows,
                isDebugLoggingEnabled: isDebugLoggingEnabled,
                currentDebugLogs: &tempLogs
            ) {
                currentDebugLogs.append(contentsOf: tempLogs)
                collector.addChildren(from: windowElementsUI)
            } else {
                currentDebugLogs.append(contentsOf: tempLogs)
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
                collectedChildren.append(childElement)
                uniqueChildrenSet.insert(childElement)
            }
        }
    }

    func finalizeResults(dLog: (String) -> Void) -> [Element]? {
        if collectedChildren.isEmpty {
            dLog("No children found for element.")
            return nil
        } else {
            dLog("Found \(collectedChildren.count) children.")
            return collectedChildren
        }
    }
}
