import ApplicationServices
import Foundation

// GlobalAXLogger should be available

// MARK: - Element Hierarchy Logic

extension Element {
    @MainActor
    private func axVerboseDebug(
        _ message: @autoclosure () -> String,
        details: [String: AnyCodable]? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line)
    {
        guard GlobalAXLogger.shared.isLoggingEnabled, GlobalAXLogger.shared.detailLevel == .verbose else { return }
        axDebugLog(message(), details: details, file: file, function: function, line: line)
    }

    @MainActor
    public func children(strict: Bool = false) -> [Element]? { // Added strict parameter
        // Logging for this top-level call
        // self.briefDescription() is assumed to be refactored and available
        self.axVerboseDebug("Getting children for element: \(self.briefDescription(option: .smart)), strict: \(strict)")

        var childCollector = ChildCollector() // ChildCollector will use GlobalAXLogger internally

        // print("[PRINT Element.children] Before collectDirectChildren for: \(self.briefDescription(option: .smart))")
        self.collectDirectChildren(collector: &childCollector)
        // print("[PRINT Element.children] After collectDirectChildren, collector has:
        // \(childCollector.collectedChildrenCount()) unique children.")

        // collectAlternativeChildren may be expensive, so respect `strict` flag there.
        if !strict {
            self.collectAlternativeChildren(collector: &childCollector)
        }

        // Always collect `AXWindows` when this element is an application. Some Electron apps only expose
        // the *front-most* window via `kAXChildrenAttribute`, while all other windows are available via
        // `kAXWindowsAttribute`.  Not including the latter caused our searches to remain inside the first
        // window (depth ≈ 37) and never reach hidden/background chat panes.  Fetching `AXWindows` every
        // time is cheap (<10 elements) and guarantees the walker can explore every window even during a
        // brute-force scan.
        self.collectApplicationWindows(collector: &childCollector)

        // Also collect AXFocusedUIElement. This exposes the single element (often a remote renderer proxy)
        // that currently has keyboard/accessibility focus – crucial for Electron/Chromium where the deep
        // subtree is not reachable through normal children. By adding it here the global traversal can
        // discover the focused textarea without requiring special path hinting.
        if self.role() == AXRoleNames.kAXApplicationRole {
            if let focusedUI: AXUIElement = attribute(Attribute(AXAttributeNames.kAXFocusedUIElementAttribute)) {
                self.axVerboseDebug("Added AXFocusedUIElement to children list for application root.")
                childCollector.addChildren(from: [focusedUI])
            }
        }

        // print("[PRINT Element.children] Before finalizeResults, collector has:
        // \(childCollector.collectedChildrenCount()) unique children.")
        let result = childCollector.finalizeResults()
        self.axVerboseDebug("Final children count: \(result?.count ?? 0)")
        return result
    }

    @MainActor
    private func collectDirectChildren(collector: inout ChildCollector) {
        self.axVerboseDebug("Attempting to fetch kAXChildrenAttribute directly.")

        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(
            self.underlyingElement,
            AXAttributeNames.kAXChildrenAttribute as CFString,
            &value)

        if error == .success {
            if let childrenCFArray = value, CFGetTypeID(childrenCFArray) == CFArrayGetTypeID() {
                if let directChildrenUI = childrenCFArray as? [AXUIElement] {
                    self.axVerboseDebug(
                        "[\(self.briefDescription(option: .smart))]: Successfully fetched and cast " +
                            "\(directChildrenUI.count) direct children.")
                    collector.addChildren(from: directChildrenUI)
                } else {
                    self.axVerboseDebug(
                        "[\(self.briefDescription(option: .smart))]: kAXChildrenAttribute was a CFArray but failed to cast " +
                            "to [AXUIElement]. TypeID: \(CFGetTypeID(childrenCFArray))")
                }
            } else if let nonArrayValue = value {
                self.axVerboseDebug(
                    "[\(self.briefDescription(option: .smart))]: kAXChildrenAttribute was not a CFArray. " +
                        "TypeID: \(CFGetTypeID(nonArrayValue)). Value: \(String(describing: nonArrayValue))")
            } else {
                self
                    .axVerboseDebug(
                        "[\(self.briefDescription(option: .smart))]: kAXChildrenAttribute was nil despite .success error code.")
            }
        } else if error == .noValue {
            self.axVerboseDebug("[\(self.briefDescription(option: .smart))]: kAXChildrenAttribute has no value.")
        } else {
            self
                .axVerboseDebug(
                    "[\(self.briefDescription(option: .smart))]: Error fetching kAXChildrenAttribute: \(error.rawValue)")
        }
    }

    @MainActor
    private func collectAlternativeChildren(collector: inout ChildCollector) {
        let alternativeAttributes: [String] = [
            AXAttributeNames.kAXVisibleChildrenAttribute, AXAttributeNames.kAXWebAreaChildrenAttribute,
            AXAttributeNames.kAXApplicationNavigationAttribute, AXAttributeNames.kAXApplicationElementsAttribute,
            AXAttributeNames.kAXBodyAreaAttribute, AXAttributeNames.kAXSplitGroupContentsAttribute,
            AXAttributeNames.kAXLayoutAreaChildrenAttribute, AXAttributeNames.kAXGroupChildrenAttribute,
            AXAttributeNames.kAXContentsAttribute, "AXChildrenInNavigationOrder",
            AXAttributeNames.kAXSelectedChildrenAttribute, AXAttributeNames.kAXRowsAttribute,
            AXAttributeNames.kAXColumnsAttribute, AXAttributeNames.kAXTabsAttribute,
        ]
        self.axVerboseDebug(
            "Using pruned attribute list (\(alternativeAttributes.count) items) " +
                "to avoid heavy payloads for alternative children.")

        for attrName in alternativeAttributes {
            self.collectChildrenFromAttribute(attributeName: attrName, collector: &collector)
        }
    }

    @MainActor
    private func collectChildrenFromAttribute(attributeName: String, collector: inout ChildCollector) {
        self.axVerboseDebug("Trying alternative child attribute: '\(attributeName)'.")
        // self.attribute() now uses GlobalAXLogger and returns T?
        if let childrenUI: [AXUIElement] = attribute(Attribute(attributeName)) {
            if !childrenUI.isEmpty {
                self.axVerboseDebug("Successfully fetched \(childrenUI.count) children from '\(attributeName)'.")
                collector.addChildren(from: childrenUI)
            } else {
                self.axVerboseDebug("Fetched EMPTY array from '\(attributeName)'.")
            }
        } else {
            // attribute() logs its own failures/nil results
            self.axVerboseDebug("Attribute '\(attributeName)' returned nil or was not [AXUIElement].")
        }
    }

    @MainActor
    private func collectApplicationWindows(collector: inout ChildCollector) {
        // self.role() now uses GlobalAXLogger and is assumed refactored
        if self.role() == AXRoleNames.kAXApplicationRole {
            self.axVerboseDebug("Element is AXApplication. Trying kAXWindowsAttribute.")
            // self.attribute() for .windows, assumed refactored
            if let windowElementsUI: [AXUIElement] = attribute(.windows) {
                if !windowElementsUI.isEmpty {
                    self.axVerboseDebug("Successfully fetched \(windowElementsUI.count) windows.")
                    collector.addChildren(from: windowElementsUI)
                } else {
                    self.axVerboseDebug("Fetched EMPTY array from kAXWindowsAttribute.")
                }
            } else {
                self.axVerboseDebug("Attribute kAXWindowsAttribute returned nil for Application element.")
            }
        }
    }
}

// MARK: - Child Collection Helper

/// Upper bound for how many children we will collect from a single element before we stop.  Some web
/// containers expose thousands of flattened descendants; 50 000 is high enough to reach any realistic
/// UI while still protecting against infinite recursion / runaway memory.
private let maxChildrenPerElement = 50000

private struct ChildCollector {
    // MARK: Public

    // New public method to get the count of unique children
    func collectedChildrenCount() -> Int {
        self.uniqueChildrenSet.count
    }

    // MARK: Internal

    mutating func addChildren(from childrenUI: [AXUIElement]) { // Removed dLog param
        if self.limitReached { return }

        for childUI in childrenUI {
            if self.collectedChildren.count >= maxChildrenPerElement {
                if !self.limitReached {
                    axWarningLog(
                        "ChildCollector: Reached maximum children limit (\(maxChildrenPerElement)). " +
                            "No more children will be added for this element.")
                    self.limitReached = true
                }
                break
            }

            let childElement = Element(childUI)
            if !self.uniqueChildrenSet.contains(childElement) {
                self.collectedChildren.append(childElement)
                self.uniqueChildrenSet.insert(childElement)
            }
        }
    }

    func finalizeResults() -> [Element]? { // Removed dLog param
        if self.collectedChildren.isEmpty {
            axDebugLog("ChildCollector: No children found after all collection methods.")
            return nil
        } else {
            axDebugLog("ChildCollector: Found \(self.collectedChildren.count) unique children.")
            return self.collectedChildren
        }
    }

    // MARK: Private

    private var collectedChildren: [Element] = []
    private var uniqueChildrenSet = Set<Element>()
    private var limitReached = false
}
