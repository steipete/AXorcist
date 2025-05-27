// CommandTypeExtensions.swift - Extensions for CommandType conversions

import AXorcist
import Foundation

// MARK: - CommandType Extension for conversion to AXCommand

extension CommandType {
    func toAXCommand(commandEnvelope: CommandEnvelope) -> AXCommand? {
        switch self {
        case .query:
            let effectiveLocator = commandEnvelope.locator ?? Locator(criteria: [])
            return .query(QueryCommand(
                appIdentifier: commandEnvelope.application,
                locator: Locator(
                    matchAll: effectiveLocator.matchAll,
                    criteria: effectiveLocator.criteria,
                    rootElementPathHint: effectiveLocator.rootElementPathHint,
                    descendantCriteria: effectiveLocator.descendantCriteria,
                    requireAction: effectiveLocator.requireAction,
                    computedNameContains: effectiveLocator.computedNameContains,
                    debugPathSearch: commandEnvelope.locator?.debugPathSearch
                ),
                attributesToReturn: commandEnvelope.attributes,
                maxDepthForSearch: commandEnvelope.maxDepth ?? 10,
                includeChildrenBrief: commandEnvelope.includeChildrenBrief
            ))
        case .performAction:
            guard let actionName = commandEnvelope.actionName else { return nil }
            return .performAction(PerformActionCommand(
                appIdentifier: commandEnvelope.application,
                locator: commandEnvelope.locator ?? Locator(criteria: []),
                action: actionName,
                value: commandEnvelope.actionValue,
                maxDepthForSearch: commandEnvelope.maxDepth ?? 10
            ))
        case .getAttributes:
            return .getAttributes(GetAttributesCommand(
                appIdentifier: commandEnvelope.application,
                locator: commandEnvelope.locator ?? Locator(criteria: []),
                attributes: commandEnvelope.attributes ?? [],
                maxDepthForSearch: commandEnvelope.maxDepth ?? 10
            ))
        case .describeElement:
            return .describeElement(DescribeElementCommand(
                appIdentifier: commandEnvelope.application,
                locator: commandEnvelope.locator ?? Locator(criteria: []),
                depth: commandEnvelope.maxDepth ?? 3,
                includeIgnored: commandEnvelope.includeIgnoredElements ?? false,
                maxSearchDepth: commandEnvelope.maxDepth ?? 10
            ))
        case .extractText:
            return .extractText(ExtractTextCommand(
                appIdentifier: commandEnvelope.application,
                locator: commandEnvelope.locator ?? Locator(criteria: []),
                maxDepthForSearch: commandEnvelope.maxDepth ?? 10,
                includeChildren: commandEnvelope.includeChildrenInText ?? false,
                maxDepth: commandEnvelope.maxDepth
            ))
        case .collectAll:
            return .collectAll(CollectAllCommand(
                appIdentifier: commandEnvelope.application,
                attributesToReturn: commandEnvelope.attributes,
                maxDepth: commandEnvelope.maxDepth ?? 10,
                filterCriteria: commandEnvelope.filterCriteria,
                valueFormatOption: ValueFormatOption.smart
            ))
        case .batch:
            guard let batchSubCommands = commandEnvelope.subCommands else {
                axErrorLog("toAXCommand: Batch command missing subCommands in CommandEnvelope.")
                return nil
            }
            let axSubCommands = batchSubCommands.compactMap { subCmdEnv -> AXBatchCommand.SubCommandEnvelope? in
                guard let axSubCmd = subCmdEnv.command.toAXCommand(commandEnvelope: subCmdEnv) else {
                    axErrorLog("toAXCommand: Failed to convert subCommand '\(subCmdEnv.commandId)' of type '\(subCmdEnv.command.rawValue)' to AXSubCommand.")
                    return nil
                }
                return AXBatchCommand.SubCommandEnvelope(commandID: subCmdEnv.commandId, command: axSubCmd)
            }
            if axSubCommands.count != batchSubCommands.count {
                axErrorLog("toAXCommand: Some subCommands in batch failed to convert. Original: \(batchSubCommands.count), Converted: \(axSubCommands.count)")
            }
            return .batch(AXBatchCommand(commands: axSubCommands))

        case .setFocusedValue:
            guard let value = commandEnvelope.actionValue?.value as? String else {
                axErrorLog("toAXCommand: SetFocusedValue missing string value in actionValue or wrong type.")
                return nil
            }
            return .setFocusedValue(SetFocusedValueCommand(
                appIdentifier: commandEnvelope.application,
                locator: commandEnvelope.locator ?? Locator(criteria: []),
                value: value,
                maxDepthForSearch: commandEnvelope.maxDepth ?? 10
            ))

        case .getElementAtPoint:
            guard let point = commandEnvelope.point else {
                axErrorLog("toAXCommand: GetElementAtPoint missing point.")
                return nil
            }
            return .getElementAtPoint(GetElementAtPointCommand(
                point: point,
                appIdentifier: commandEnvelope.application,
                pid: commandEnvelope.pid,
                attributesToReturn: commandEnvelope.attributes,
                includeChildrenBrief: commandEnvelope.includeChildrenBrief
            ))

        case .getFocusedElement:
            return .getFocusedElement(GetFocusedElementCommand(
                appIdentifier: commandEnvelope.application,
                attributesToReturn: commandEnvelope.attributes,
                includeChildrenBrief: commandEnvelope.includeChildrenBrief
            ))

        case .observe:
            guard let notificationsList = commandEnvelope.notifications, !notificationsList.isEmpty else {
                axErrorLog("toAXCommand: Observe missing notifications list.")
                return nil
            }
            guard let firstNotificationName = notificationsList.first,
                  let axNotification = AXNotification(rawValue: firstNotificationName) else {
                axErrorLog("toAXCommand: Invalid or unsupported notification name: \(notificationsList.first ?? "nil") for observe command.")
                return nil
            }
            return .observe(ObserveCommand(
                appIdentifier: commandEnvelope.application,
                locator: commandEnvelope.locator,
                notifications: notificationsList,
                includeDetails: true,
                watchChildren: commandEnvelope.watchChildren ?? false,
                notificationName: axNotification,
                includeElementDetails: commandEnvelope.includeElementDetails,
                maxDepthForSearch: commandEnvelope.maxDepth ?? 10
            ))

        case .ping:
            return nil

        case .stopObservation:
            return nil

        case .isProcessTrusted:
            return nil

        case .isAXFeatureEnabled:
            return nil

        case .setNotificationHandler:
            return nil

        case .removeNotificationHandler:
            return nil

        case .getElementDescription:
            return nil
        }
    }
}
