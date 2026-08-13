import Foundation

enum AXTraversalOrder {
    case depthFirst
    case breadthFirst
}

struct AXTraversalResult {
    let visitedCount: Int
    let timedOut: Bool
    let stopped: Bool
}

typealias AXTraversalClock = @MainActor () -> TimeInterval
typealias AXTraversalChildrenProvider = @MainActor (Element, Bool) -> [Element]?

struct AXTraversalExecutionPolicy {
    let options: AXTraversalOptions
    let now: AXTraversalClock

    init(
        options: AXTraversalOptions,
        now: @escaping AXTraversalClock = { ProcessInfo.processInfo.systemUptime })
    {
        self.options = options
        self.now = now
    }
}

private struct AXTraversalPendingElement {
    let element: Element
    let depth: Int
}

private struct AXTraversalState {
    var pending: [AXTraversalPendingElement]
    var breadthIndex = 0
    var visited = Set<Element>()

    init(root: Element, initialDepth: Int) {
        self.pending = [AXTraversalPendingElement(element: root, depth: initialDepth)]
    }

    func hasPending(order: AXTraversalOrder) -> Bool {
        switch order {
        case .depthFirst:
            !self.pending.isEmpty
        case .breadthFirst:
            self.breadthIndex < self.pending.count
        }
    }

    mutating func removeNext(order: AXTraversalOrder) -> AXTraversalPendingElement {
        switch order {
        case .depthFirst:
            return self.pending.removeLast()
        case .breadthFirst:
            defer { self.breadthIndex += 1 }
            return self.pending[self.breadthIndex]
        }
    }

    mutating func appendChildren(
        _ children: [Element],
        parentDepth: Int,
        order: AXTraversalOrder)
    {
        let orderedChildren: [Element] = switch order {
        case .depthFirst:
            Array(children.reversed())
        case .breadthFirst:
            children
        }
        self.pending.append(contentsOf: orderedChildren.map {
            AXTraversalPendingElement(element: $0, depth: parentDepth + 1)
        })
    }
}

/// The single identity-aware tree walker used by AXorcist's downward traversal surfaces.
@MainActor
@discardableResult
func traverseAXTree(
    from root: Element,
    initialDepth: Int = 0,
    maxDepth: Int? = nil,
    order: AXTraversalOrder = .depthFirst,
    strictChildren: Bool = false,
    timeout: TimeInterval? = nil,
    now: AXTraversalClock = { ProcessInfo.processInfo.systemUptime },
    children: AXTraversalChildrenProvider = { element, strict in element.children(strict: strict) },
    shouldDescend: (Element, Int) -> Bool = { _, _ in true },
    onTimeout: () -> Void = {},
    visit: (Element, Int) -> TreeVisitorResult) -> AXTraversalResult
{
    let deadline = timeout.map { now() + $0 }
    var state = AXTraversalState(root: root, initialDepth: initialDepth)
    var timedOut = false
    var stopped = false

    while state.hasPending(order: order) {
        let next = state.removeNext(order: order)
        if let deadline, now() > deadline {
            timedOut = true
            onTimeout()
            break
        }
        if let maxDepth, next.depth > maxDepth {
            continue
        }
        guard state.visited.insert(next.element).inserted else {
            continue
        }

        let visitResult = visit(next.element, next.depth)
        switch visitResult {
        case .stop:
            stopped = true
        case .skipChildren:
            continue
        case .continue:
            break
        }
        if stopped {
            break
        }
        guard shouldDescend(next.element, next.depth) else {
            continue
        }
        if let maxDepth, next.depth >= maxDepth {
            continue
        }
        guard let childElements = children(next.element, strictChildren), !childElements.isEmpty else {
            continue
        }

        state.appendChildren(childElements, parentDepth: next.depth, order: order)
    }

    return AXTraversalResult(
        visitedCount: state.visited.count,
        timedOut: timedOut,
        stopped: stopped)
}
