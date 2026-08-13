import ApplicationServices
import Foundation
import Testing
@testable import AXorcist

@Suite("Canonical accessibility traversal", .serialized)
@MainActor
struct TraversalKernelTests {
    @Test
    func `Depth-first traversal terminates cycles and visits diamond identities once`() {
        let shared = self.element(pid: 2_020_000_004, title: "shared")
        let left = self.element(pid: 2_020_000_002, title: "left", children: [shared])
        let right = self.element(pid: 2_020_000_003, title: "right", children: [shared])
        let diamond = self.element(pid: 2_020_000_001, title: "root", children: [left, right])

        #expect(self.visitedTitles(from: diamond) == ["root", "left", "shared", "right"])

        let cycleIdentity = AXUIElementCreateApplication(2_020_000_010)
        let rootAlias = self.element(identity: cycleIdentity, title: "root-alias")
        let child = self.element(pid: 2_020_000_011, title: "child", children: [rootAlias])
        let cycle = self.element(identity: cycleIdentity, title: "root", children: [child])

        #expect(self.visitedTitles(from: cycle) == ["root", "child"])
    }

    @Test
    func `Shallower diamond path re-expands descendants without duplicate visitor emission`() {
        let leaf = self.element(pid: 2_020_000_016, title: "leaf")
        let shared = self.element(pid: 2_020_000_015, title: "shared", children: [leaf])
        let deepParent = self.element(pid: 2_020_000_014, title: "deep-parent", children: [shared])
        let longBranch = self.element(pid: 2_020_000_013, title: "long", children: [deepParent])
        let shortBranch = self.element(pid: 2_020_000_012, title: "short", children: [shared])
        let root = self.element(pid: 2_020_000_017, title: "root", children: [longBranch, shortBranch])
        let visitor = RecordingVisitor()

        traverseAndSearch(
            element: root,
            visitor: visitor,
            currentDepth: 0,
            maxDepth: 3,
            traversalOptions: AXTraversalOptions(scanAll: true))

        #expect(visitor.titles == ["root", "long", "deep-parent", "shared", "short", "leaf"])
    }

    @Test
    func `Kernel preserves depth-first breadth-first depth and strict policies`() {
        let root = self.element(pid: 2_020_000_020, title: "root")
        let left = self.element(pid: 2_020_000_021, title: "left")
        let right = self.element(pid: 2_020_000_022, title: "right")
        let leaf = self.element(pid: 2_020_000_023, title: "leaf")
        let childrenByElement = [
            root: [left, right],
            left: [leaf],
        ]
        var strictArguments: [Bool] = []

        var depthFirst: [String] = []
        traverseAXTree(
            from: root,
            maxDepth: 1,
            strictChildren: true,
            children: { element, strict in
                strictArguments.append(strict)
                return childrenByElement[element]
            },
            visit: { element, _ in
                depthFirst.append(element.title() ?? "")
                return .continue
            })
        #expect(depthFirst == ["root", "left", "right"])
        #expect(strictArguments == [true])

        var breadthFirst: [String] = []
        traverseAXTree(
            from: root,
            order: .breadthFirst,
            children: { element, _ in childrenByElement[element] },
            visit: { element, _ in
                breadthFirst.append(element.title() ?? "")
                return .continue
            })
        #expect(breadthFirst == ["root", "left", "right", "leaf"])
    }

    @Test
    func `Injected clock stops traversal deterministically`() {
        let grandchild = self.element(pid: 2_020_000_033, title: "grandchild")
        let child = self.element(pid: 2_020_000_032, title: "child", children: [grandchild])
        let root = self.element(pid: 2_020_000_031, title: "root", children: [child])
        var instants: [TimeInterval] = [0, 0, 0.5, 2]
        let visitor = RecordingVisitor()

        traverseAndSearch(
            element: root,
            visitor: visitor,
            currentDepth: 0,
            maxDepth: 2,
            executionPolicy: AXTraversalExecutionPolicy(
                options: AXTraversalOptions(timeout: 1, scanAll: true),
                now: { instants.removeFirst() }))

        #expect(visitor.titles == ["root", "child"])
        #expect(instants.isEmpty)
    }

    @Test
    func `Canonical collection and Element search surfaces preserve preorder`() {
        let shared = self.element(pid: 2_020_000_044, title: "node-shared", identifier: "shared-id")
        let left = self.element(pid: 2_020_000_042, title: "node-left", children: [shared])
        let right = self.element(pid: 2_020_000_043, title: "node-right", children: [shared])
        let root = self.element(pid: 2_020_000_041, title: "node-root", children: [left, right])
        let expected = [root, left, shared, right]

        #expect(collectAllElements(
            from: root,
            maxDepth: 3,
            includeIgnored: true,
            traversalOptions: AXTraversalOptions(scanAll: true)) == expected)
        #expect(root.searchElements(matching: "node-") == expected)
        #expect(root.findElements() == expected)
        #expect(root.findElement(byIdentifier: "shared-id") == shared)

        var depthOneOptions = ElementSearchOptions()
        depthOneOptions.maxDepth = 1
        #expect(root.searchElements(matching: "node-", options: depthOneOptions) == [root, left, right])
        #expect(root.findElements(maxDepth: 1) == [root, left, right])
    }

    @Test
    func `Search visitor preserves last-match and first-match semantics`() {
        let first = self.element(pid: 2_020_000_052, title: "first", role: AXRoleNames.kAXButtonRole)
        let second = self.element(pid: 2_020_000_053, title: "second", role: AXRoleNames.kAXButtonRole)
        let root = self.element(pid: 2_020_000_051, title: "root", children: [first, second])
        let criterion = Criterion(attribute: AXAttributeNames.kAXRoleAttribute, value: AXRoleNames.kAXButtonRole)

        let lastMatch = SearchVisitor(criteria: [criterion], stopAtFirstMatch: false, maxDepth: 1)
        traverseAndSearch(
            element: root,
            visitor: lastMatch,
            currentDepth: 0,
            maxDepth: 1,
            traversalOptions: AXTraversalOptions(scanAll: true, stopAtFirstMatch: false))
        #expect(lastMatch.foundElement == second)
        #expect(lastMatch.allFoundElements == [first, second])

        let firstMatch = SearchVisitor(criteria: [criterion], stopAtFirstMatch: true, maxDepth: 1)
        traverseAndSearch(
            element: root,
            visitor: firstMatch,
            currentDepth: 0,
            maxDepth: 1,
            traversalOptions: AXTraversalOptions(scanAll: true, stopAtFirstMatch: true))
        #expect(firstMatch.foundElement == first)
        #expect(firstMatch.allFoundElements == [first])
    }

    @Test
    func `Deep JSON path keeps breadth-first first-match order`() {
        let deep = self.element(pid: 2_020_000_064, title: "target")
        let left = self.element(pid: 2_020_000_062, title: "left", children: [deep])
        let shallow = self.element(pid: 2_020_000_063, title: "target")
        let root = self.element(pid: 2_020_000_061, title: "root", children: [left, shallow])

        let result = navigateToElementByJSONPathHint(
            from: root,
            jsonPathHint: [JSONPathHintComponent(attribute: "TITLE", value: "target", depth: 2)])

        #expect(result == shallow)
    }

    private func visitedTitles(from root: Element) -> [String] {
        let visitor = RecordingVisitor()
        traverseAndSearch(
            element: root,
            visitor: visitor,
            currentDepth: 0,
            maxDepth: 20,
            traversalOptions: AXTraversalOptions(scanAll: true))
        return visitor.titles
    }

    private func element(
        pid: pid_t,
        title: String,
        role: String = AXRoleNames.kAXGroupRole,
        identifier: String? = nil,
        children: [Element] = []) -> Element
    {
        self.element(
            identity: AXUIElementCreateApplication(pid),
            title: title,
            role: role,
            identifier: identifier,
            children: children)
    }

    private func element(
        identity: AXUIElement,
        title: String,
        role: String = AXRoleNames.kAXGroupRole,
        identifier: String? = nil,
        children: [Element] = []) -> Element
    {
        var attributes: [String: AttributeValue] = [
            AXAttributeNames.kAXRoleAttribute: .string(role),
            AXAttributeNames.kAXTitleAttribute: .string(title),
        ]
        if let identifier {
            attributes[AXAttributeNames.kAXIdentifierAttribute] = .string(identifier)
        }
        return Element(identity, attributes: attributes, children: children, actions: [])
    }
}

@MainActor
private final class RecordingVisitor: ElementVisitor {
    private(set) var titles: [String] = []

    func visit(element: Element, depth _: Int) -> TreeVisitorResult {
        self.titles.append(element.title() ?? "")
        return .continue
    }
}
