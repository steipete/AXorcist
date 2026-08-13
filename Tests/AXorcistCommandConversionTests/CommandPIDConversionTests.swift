import CoreGraphics
import Testing
@testable import axorc
@testable import AXorcist

@Suite("Command PID conversion")
@MainActor
struct CommandPIDConversionTests {
    @Test
    func `CLI conversion preserves PID for every targeted command`() {
        let expectedPID = 91337
        let locator = Locator(criteria: [
            Criterion(attribute: AXAttributeNames.kAXRoleAttribute, value: AXRoleNames.kAXButtonRole),
        ])
        let commands: [CommandEnvelope] = [
            .init(commandId: "query", command: .query, locator: locator, pid: expectedPID),
            .init(
                commandId: "action",
                command: .performAction,
                locator: locator,
                actionName: AXActionNames.kAXPressAction,
                pid: expectedPID),
            .init(
                commandId: "attributes",
                command: .getAttributes,
                attributes: [AXAttributeNames.kAXTitleAttribute],
                locator: locator,
                pid: expectedPID),
            .init(commandId: "describe", command: .describeElement, locator: locator, pid: expectedPID),
            .init(commandId: "extract", command: .extractText, locator: locator, pid: expectedPID),
            .init(commandId: "collect", command: .collectAll, pid: expectedPID),
            .init(
                commandId: "value",
                command: .setFocusedValue,
                locator: locator,
                actionValue: AnyCodable("value"),
                pid: expectedPID),
            .init(commandId: "focused", command: .getFocusedElement, pid: expectedPID),
            .init(
                commandId: "observe",
                command: .observe,
                locator: locator,
                pid: expectedPID,
                notifications: [AXNotification.valueChanged.rawValue]),
            .init(
                commandId: "point",
                command: .getElementAtPoint,
                point: CGPoint(x: 1, y: 2),
                pid: expectedPID),
        ]

        for envelope in commands {
            guard let command = envelope.command.toAXCommand(commandEnvelope: envelope) else {
                Issue.record("Failed to convert \(envelope.command.rawValue)")
                continue
            }
            #expect(self.targetPID(in: command) == expectedPID)
        }
    }

    private func targetPID(in command: AXCommand) -> Int? {
        switch command {
        case let .query(command): command.pid
        case let .performAction(command): command.pid
        case let .getAttributes(command): command.pid
        case let .describeElement(command): command.pid
        case let .extractText(command): command.pid
        case let .setFocusedValue(command): command.pid
        case let .getElementAtPoint(command): command.pid
        case let .getFocusedElement(command): command.pid
        case let .observe(command): command.pid
        case let .collectAll(command): command.pid
        case .batch: nil
        }
    }
}
