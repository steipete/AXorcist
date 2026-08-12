import ApplicationServices
import Testing
@testable import AXorcist

@Suite("Accessibility tree traversal state")
@MainActor
struct TraversalStateTests {
    @Test
    func `Repeated traversals use independent visited sets`() {
        let child = self.element(pid: 2_000_000_002, role: AXRoleNames.kAXButtonRole)
        let root = self.element(pid: 2_000_000_001, role: AXRoleNames.kAXApplicationRole, children: [child])

        #expect(root.children() == [child])

        let firstVisitor = CountingVisitor()
        traverseAndSearch(element: root, visitor: firstVisitor, currentDepth: 0, maxDepth: 2)

        let secondVisitor = CountingVisitor()
        traverseAndSearch(element: root, visitor: secondVisitor, currentDepth: 0, maxDepth: 2)

        #expect(firstVisitor.visitCount == 2)
        #expect(secondVisitor.visitCount == 2)
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
private final class CountingVisitor: ElementVisitor {
    private(set) var visitCount = 0

    func visit(element _: Element, depth _: Int) -> TreeVisitorResult {
        self.visitCount += 1
        return .continue
    }
}
