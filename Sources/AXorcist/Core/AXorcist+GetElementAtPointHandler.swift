import ApplicationServices
import Foundation

@MainActor
extension AXorcist {
    public func handleGetElementAtPoint(command: GetElementAtPointCommand) -> AXResponse {
        self.executeGetElementAtPoint(
            command: command,
            applicationResolver: nativeApplicationElement,
            elementResolver: Element.elementAtPoint)
    }

    func executeGetElementAtPoint(
        command: GetElementAtPointCommand,
        applicationResolver: AXApplicationElementResolver,
        elementResolver: (CGPoint, pid_t) -> Element?) -> AXResponse
    {
        self.logGetPointRequest(command)

        let resolvedTarget: AXResolvedApplicationTarget
        switch resolveApplicationTarget(
            appIdentifier: command.appIdentifier,
            pid: command.pid,
            using: applicationResolver)
        {
        case let .success(target):
            resolvedTarget = target
        case let .failure(error):
            return error.response
        }

        self.logContextElement(resolvedTarget.element)

        guard let pid = resolvedTarget.element.pid(), pid > 0 else {
            return AXCommandTargetError.applicationNotFound(
                "Could not determine the PID for \(resolvedTarget.target.description).").response
        }
        guard let element = elementResolver(command.point, pid) else {
            return self.noElementResponse(command: command, target: resolvedTarget.target)
        }
        guard element.pid() == pid else {
            return AXCommandTargetError.elementNotFound(
                "The element at the requested point did not belong to \(resolvedTarget.target.description).").response
        }

        self.logLocatedElement(element)
        return .successResponse(payload: AnyCodable(self.elementData(from: element)))
    }

    private func logGetPointRequest(_ command: GetElementAtPointCommand) {
        let target = command.appIdentifier ?? "focused"
        let point = "[\(command.point.x), \(command.point.y)]"
        let pidDescription = command.pid.map(String.init) ?? "0"
        let message = "HandleGetElementAtPoint: App '\(target)', Point: \(point), PID: \(pidDescription)"
        GlobalAXLogger.shared.log(AXLogEntry(level: .info, message: message))
    }

    private func logContextElement(_ element: Element) {
        let description = element.briefDescription(option: .smart)
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "Context app element: \(description)"))
    }

    private func noElementResponse(
        command: GetElementAtPointCommand,
        target: AXApplicationTarget) -> AXResponse
    {
        let point = "[\(command.point.x), \(command.point.y)]"
        let message = "No UI element found at \(point) for \(target.description)."
        GlobalAXLogger.shared.log(AXLogEntry(level: .info, message: message))
        return .errorResponse(message: message, code: .elementNotFound)
    }

    private func logLocatedElement(_ element: Element) {
        let description = element.briefDescription(option: .smart)
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "Element at point: \(description)"))
    }

    private func elementData(from element: Element) -> AXElementData {
        AXElementData(
            briefDescription: element.briefDescription(option: .smart),
            role: element.role(),
            attributes: [:],
            allPossibleAttributes: element.attributeNames(),
            textualContent: nil,
            childrenBriefDescriptions: nil,
            fullAXDescription: element.briefDescription(option: .stringified),
            path: element.generatePathString().components(separatedBy: " -> "))
    }
}
