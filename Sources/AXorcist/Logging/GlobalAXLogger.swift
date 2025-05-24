import Foundation
import os // For OSLog specific configurations if ever needed directly.

// Ensure AXLogEntry is Sendable
// public struct AXLogEntry: Codable, Identifiable, Sendable { ... }

public actor GlobalAXLogger {
    public static let shared = GlobalAXLogger()

    private var logEntries: [AXLogEntry] = []
    // private var subscribers: [UUID: @MainActor (AXLogEntry) -> Void] = [:] // REMOVED

    // Publicly accessible for direct checks if needed, though usually consumers use subscription.
    public var isJSONLoggingEnabled: Bool = false

    private init() {
        // Check environment variable for JSON logging preference on init
        if let envVar = ProcessInfo.processInfo.environment["AXORC_JSON_LOG_ENABLED"], envVar.lowercased() == "true" {
            isJSONLoggingEnabled = true
            // Use fputs for direct stderr output to avoid os_log/print overhead if pure JSON is desired
            fputs("{\\\"axorc_log_stream_type\\\": \\\"json_objects\\\", \\\"status\\\": \\\"AXGlobalLogger initialized with JSON output to stderr.\"}\\n", stderr)
        }
    }

    // MARK: - Logging Core
    // This method is called by the global ax...Log functions.
    // It's actor-isolated, so access to logEntries is serialized.
    func log(_ entry: AXLogEntry) {
        logEntries.append(entry)

        // JSON logging to stderr if enabled
        if isJSONLoggingEnabled {
            do {
                let jsonData = try JSONEncoder().encode(entry)
                if let jsonString = String(data: jsonData, encoding: .utf8) {
                    fputs(jsonString + "\\n", stderr) // Output JSON string to stderr
                }
            } catch {
                // Fallback or error logging for JSON serialization failure
                fputs("{\\\"error\\\": \\\"Failed to serialize AXLogEntry to JSON: \\(error.localizedDescription)\\\"}\\n", stderr)
            }
        }

        // REMOVED SUBSCRIBER LOOP
        // subscribers.values.forEach { subscriber in
        //     // The subscriber closure expects to be called on the MainActor.
        //     // AXLogEntry must be Sendable.
        //     Task { @MainActor in
        //         subscriber(entry)
        //     }
        // }
    }

    // MARK: - Log Retrieval
    // These methods are also actor-isolated.
    func getEntries() -> [AXLogEntry] {
        return logEntries
    }

    func clearEntries() {
        logEntries.removeAll()
        // Optionally log the clear action itself if needed, depending on requirements.
        // let clearEntry = AXLogEntry(level: .info, message: "GlobalAXLogger log entries cleared.")
        // logEntries.append(clearEntry) // careful about re-entrancy or immediate re-logging
    }

    // MARK: - Subscription Management (REMOVED)
    /*
    func subscribeToLogs(_ onNewLog: @escaping @MainActor (AXLogEntry) -> Void) -> UUID {
        let id = UUID()
        subscribers[id] = onNewLog
        return id
    }

    func unsubscribeFromLogs(subscriberId: UUID) {
        subscribers.removeValue(forKey: subscriberId)
    }
    */
}

// MARK: - Global Logging Functions (Convenience Wrappers)
// These call into the actor's log method.

// ... (axDebugLog, axInfoLog, etc. remain unchanged) ...

// MARK: - Global Log Access Functions (Convenience Wrappers for actor methods)

// Fetches all log entries directly from the actor.
public func axGetLogEntries() async -> [AXLogEntry] {
    return await GlobalAXLogger.shared.getEntries()
}

// Clears all log entries in the actor.
public func axClearLogs() async {
    await GlobalAXLogger.shared.clearEntries()
}

// MARK: - Global Subscription Wrappers (REMOVED)
/*
// Subscribes to new log entries. The callback is invoked on the MainActor.
// The returned UUID can be used to unsubscribe later.
@MainActor
public func axSubscribeToLogs(_ onNewLog: @escaping (AXLogEntry) -> Void) async -> UUID {
    return await GlobalAXLogger.shared.subscribeToLogs(onNewLog)
}

// Unsubscribes from log entries using the ID obtained from axSubscribeToLogs.
public func axUnsubscribeFromLogs(subscriberId: UUID) async {
    await GlobalAXLogger.shared.unsubscribeFromLogs(subscriberId: subscriberId)
}
*/
// MARK: - Environment Variable Check for JSON Logging (REMOVED - handled in init)
// private func checkJSONLoggingEnvironmentVariable() -> Bool { ... }

// MARK: - Public Property for JSON Logging State (REMOVED - handled by actor's property)
// public var isAXJSONLoggingEnabled: Bool { ... }
