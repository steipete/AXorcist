import ApplicationServices
import Dispatch
import Foundation
import os
import Testing
@testable import axorc
@testable import AXorcist

@Suite("Accessibility traversal options", .serialized)
@MainActor
struct TraversalOptionsTests {
    @Test
    func `Standard options are immutable Sendable values`() {
        self.requireSendable(AXTraversalOptions.standard)
        #expect(AXTraversalOptions.standard == AXTraversalOptions(
            timeout: 30,
            scanAll: false,
            stopAtFirstMatch: true))
    }

    @available(*, deprecated, message: "Exercises the retained legacy compatibility surface.")
    @Test
    func `Legacy globals remain source compatible and preserve sibling defaults`() {
        let original = AXTraversalOptions.snapshotDefaults()
        defer { AXTraversalOptions.replaceDefaults(original) }

        axorcTraversalTimeout = 7
        axorcScanAll = true
        axorcStopAtFirstMatch = false

        #expect(axorcTraversalTimeout == 7)
        #expect(axorcScanAll)
        #expect(!axorcStopAtFirstMatch)
        #expect(AXTraversalOptions.snapshotDefaults() == AXTraversalOptions(
            timeout: 7,
            scanAll: true,
            stopAtFirstMatch: false))
    }

    @available(*, deprecated, message: "Exercises the retained legacy compatibility surface.")
    @Test
    func `Legacy traversal snapshots defaults before a visitor flips them`() {
        let original = AXTraversalOptions.snapshotDefaults()
        defer { AXTraversalOptions.replaceDefaults(original) }
        AXTraversalOptions.replaceDefaults(AXTraversalOptions(
            timeout: 30,
            scanAll: true,
            stopAtFirstMatch: true))

        let root = self.testTree()
        let flippingVisitor = TraversalOptionsCountingVisitor { depth in
            if depth == 0 {
                axorcScanAll = false
            }
        }

        let legacyTraversal: @MainActor (Element, any ElementVisitor, Int, Int) -> Void = traverseAndSearch
        legacyTraversal(root, flippingVisitor, 0, 2)
        #expect(flippingVisitor.visitCount == 3)

        let nextVisitor = TraversalOptionsCountingVisitor()
        legacyTraversal(root, nextVisitor, 0, 2)
        #expect(nextVisitor.visitCount == 2)
    }

    @Test
    func `Opposite explicit options do not consult process defaults`() {
        let original = AXTraversalOptions.snapshotDefaults()
        defer { AXTraversalOptions.replaceDefaults(original) }
        AXTraversalOptions.replaceDefaults(AXTraversalOptions(
            timeout: -1,
            scanAll: false,
            stopAtFirstMatch: false))

        let root = self.testTree()
        let exhaustiveVisitor = TraversalOptionsCountingVisitor()
        traverseAndSearch(
            element: root,
            visitor: exhaustiveVisitor,
            currentDepth: 0,
            maxDepth: 2,
            traversalOptions: AXTraversalOptions(
                timeout: 30,
                scanAll: true,
                stopAtFirstMatch: true))
        #expect(exhaustiveVisitor.visitCount == 3)

        let prunedVisitor = TraversalOptionsCountingVisitor()
        traverseAndSearch(
            element: root,
            visitor: prunedVisitor,
            currentDepth: 0,
            maxDepth: 2,
            traversalOptions: AXTraversalOptions(
                timeout: 30,
                scanAll: false,
                stopAtFirstMatch: false))
        #expect(prunedVisitor.visitCount == 2)
    }

    @Test
    func `Concurrent default replacements never expose torn options`() {
        let original = AXTraversalOptions.snapshotDefaults()
        defer { AXTraversalOptions.replaceDefaults(original) }
        let first = AXTraversalOptions(timeout: 1, scanAll: false, stopAtFirstMatch: true)
        let second = AXTraversalOptions(timeout: 2, scanAll: true, stopAtFirstMatch: false)
        let failures = OSAllocatedUnfairLock(initialState: [AXTraversalOptions]())
        AXTraversalOptions.replaceDefaults(first)

        DispatchQueue.concurrentPerform(iterations: 2000) { index in
            if index.isMultiple(of: 3) {
                AXTraversalOptions.replaceDefaults(index.isMultiple(of: 2) ? first : second)
            } else {
                let snapshot = AXTraversalOptions.snapshotDefaults()
                if snapshot != first, snapshot != second {
                    failures.withLock { $0.append(snapshot) }
                }
            }
        }

        #expect(failures.withLock { $0.isEmpty })
    }

    @Test
    func `Raw CLI resolves one explicit request snapshot without timeout bleed`() {
        let original = AXTraversalOptions.snapshotDefaults()
        defer { AXTraversalOptions.replaceDefaults(original) }
        AXTraversalOptions.replaceDefaults(AXTraversalOptions(
            timeout: -1,
            scanAll: true,
            stopAtFirstMatch: false))

        var defaultsCommand = AXORCCommand()
        #expect(defaultsCommand.resolvedTraversalOptions() == .standard)

        defaultsCommand.timeout = 9
        defaultsCommand.scanAll = true
        defaultsCommand.noStopFirst = true
        #expect(defaultsCommand.resolvedTraversalOptions() == AXTraversalOptions(
            timeout: 9,
            scanAll: true,
            stopAtFirstMatch: false))
    }

    private func requireSendable(_ value: some Sendable) {
        _ = value
    }

    private func testTree() -> Element {
        let grandchild = self.element(
            pid: 2_100_000_003,
            role: AXRoleNames.kAXStaticTextRole)
        let child = self.element(
            pid: 2_100_000_002,
            role: AXRoleNames.kAXButtonRole,
            children: [grandchild])
        return self.element(
            pid: 2_100_000_001,
            role: AXRoleNames.kAXApplicationRole,
            children: [child])
    }

    private func element(pid: pid_t, role: String, children: [Element] = []) -> Element {
        Element(
            AXUIElementCreateApplication(pid),
            attributes: [
                AXAttributeNames.kAXRoleAttribute: .string(role),
                AXAttributeNames.kAXTitleAttribute: .string("test-\(pid)"),
            ],
            children: children,
            actions: [])
    }
}

@MainActor
private final class TraversalOptionsCountingVisitor: ElementVisitor {
    private(set) var visitCount = 0
    private let onVisit: (Int) -> Void

    init(onVisit: @escaping (Int) -> Void = { _ in }) {
        self.onVisit = onVisit
    }

    func visit(element _: Element, depth: Int) -> TreeVisitorResult {
        self.visitCount += 1
        self.onVisit(depth)
        return .continue
    }
}
