import Foundation

// Ensure AXLogEntry and AXLogLevel are importable, potentially from AXorcistLib itself or another shared module.

@globalActor
public actor GlobalAXLogger {
    public static let shared = GlobalAXLogger()

    private var logEntries: [AXLogEntry] = []
    private var logSubscribers: [UUID: @MainActor (AXLogEntry) -> Void] = [:]

    private init() { // Private to ensure singleton
        // Potentially load historical logs or configure based on environment
    }

    // MARK: - Logging Methods
    public func log(
        level: AXLogLevel,
        message: String,
        file: String? = #file,
        function: String? = #function,
        line: Int? = #line,
        details: [String: String]? = nil
    ) {
        let entry = AXLogEntry(
            level: level,
            message: message,
            file: file,
            function: function,
            line: line,
            details: details
        )
        logEntries.append(entry)

        // Notify subscribers
        for subscriber in logSubscribers.values {
            // The subscriber closure expects to be called on the MainActor.
            // AXLogEntry must be Sendable.
            Task { @MainActor in
                subscriber(entry)
            }
        }

        // Optional: Print to console for immediate visibility during development
        // print(entry.formattedForTextLog()) // Or a JSON format
    }

    // Convenience methods for different log levels
    public func debug(_ message: String, details: [String: String]? = nil, file: String? = #file, function: String? = #function, line: Int? = #line) {
        log(level: .debug, message: message, file: file, function: function, line: line, details: details)
    }

    public func info(_ message: String, details: [String: String]? = nil, file: String? = #file, function: String? = #function, line: Int? = #line) {
        log(level: .info, message: message, file: file, function: function, line: line, details: details)
    }

    public func warning(_ message: String, details: [String: String]? = nil, file: String? = #file, function: String? = #function, line: Int? = #line) {
        log(level: .warning, message: message, file: file, function: function, line: line, details: details)
    }

    public func error(_ message: String, details: [String: String]? = nil, file: String? = #file, function: String? = #function, line: Int? = #line) {
        log(level: .error, message: message, file: file, function: function, line: line, details: details)
    }

    public func critical(_ message: String, details: [String: String]? = nil, file: String? = #file, function: String? = #function, line: Int? = #line) {
        log(level: .critical, message: message, file: file, function: function, line: line, details: details)
    }

    // MARK: - Log Retrieval and Management

    public func getLogEntries() -> [AXLogEntry] {
        return logEntries
    }

    public func clearLogs() {
        logEntries.removeAll()
    }

    public func getLogEntriesAsJSON(options: JSONEncoder.OutputFormatting = []) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = options
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(logEntries)
        return String(data: jsonData, encoding: .utf8) ?? "[]"
    }

    public func getLogEntriesAsText() -> String {
        return logEntries.map { $0.formattedForTextLog() }.joined(separator: "\n")
    }

    // MARK: - Subscription Management

    /// Allows external components to subscribe to new log entries.
    /// - Parameter onNewLog: A closure that will be called with each new log entry.
    ///                       This closure will be executed on the MainActor.
    /// - Returns: A UUID that can be used to unsubscribe.
    public func subscribeToLogs(_ onNewLog: @escaping @MainActor (AXLogEntry) -> Void) -> UUID {
        let subscriberId = UUID()
        logSubscribers[subscriberId] = onNewLog
        return subscriberId
    }

    /// Unsubscribes a component from log updates.
    /// - Parameter subscriberId: The UUID returned from `subscribeToLogs`.
    public func unsubscribeFromLogs(subscriberId: UUID) {
        logSubscribers.removeValue(forKey: subscriberId)
    }
}

// MARK: - Public API for Global Logging
// The main logging functions are defined in LoggingHelpers.swift
// They use @autoclosure for better performance and cleaner syntax

@MainActor
public func axGetAllLogs() async -> [AXLogEntry] {
    return await GlobalAXLogger.shared.getLogEntries()
}

@MainActor
public func axClearLogs() async {
    await GlobalAXLogger.shared.clearLogs()
}

@MainActor
public func axGetLogsAsJSON(options: JSONEncoder.OutputFormatting = []) async throws -> String {
    return try await GlobalAXLogger.shared.getLogEntriesAsJSON(options: options)
}

@MainActor
public func axGetLogsAsText() async -> String {
    return await GlobalAXLogger.shared.getLogEntriesAsText()
}

@MainActor
public func axSubscribeToLogs(_ onNewLog: @escaping (AXLogEntry) -> Void) async -> UUID {
    return await GlobalAXLogger.shared.subscribeToLogs(onNewLog)
}

@MainActor
public func axUnsubscribeFromLogs(subscriberId: UUID) async {
    await GlobalAXLogger.shared.unsubscribeFromLogs(subscriberId: subscriberId)
}
