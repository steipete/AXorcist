import Foundation
import os // For OSLog specific configurations if ever needed directly.

// Ensure AXLogEntry is Sendable - this might not be strictly necessary if logger is fully synchronous
// and not passing entries across actor boundaries, but good for robustness.
// public struct AXLogEntry: Codable, Identifiable, Sendable { ... }

public class GlobalAXLogger {
    public static let shared = GlobalAXLogger()

    private var logEntries: [AXLogEntry] = []
    // For duplicate suppression
    private var lastCondensedMessage: String? = nil
    private var duplicateCount: Int = 0
    private let duplicateSummaryThreshold: Int = 5
    // Maximum characters to keep in a log message before truncating (for readability)
    private let maxMessageLength: Int = 300
    
    // No DispatchQueue needed if all calls are on the main thread.
    // Callers must ensure main-thread execution for all logger interactions.

    public var isJSONLoggingEnabled: Bool = false // Direct access, assuming main-thread safety

    private init() {
        if let envVar = ProcessInfo.processInfo.environment["AXORC_JSON_LOG_ENABLED"], envVar.lowercased() == "true" {
            isJSONLoggingEnabled = true
            fputs("{\\\"axorc_log_stream_type\\\": \\\"json_objects\\\", \\\"status\\\": \\\"AXGlobalLogger initialized with JSON output to stderr.\"}\n", stderr)
        }
    }

    // MARK: - Logging Core
    // Assumes this method is always called on the main thread.
    public func log(_ entry: AXLogEntry) {
        let condensedMessage: String = {
            if entry.message.count > maxMessageLength {
                let prefix = entry.message.prefix(maxMessageLength)
                return "\(prefix)… (\(entry.message.count) chars)"
            } else {
                return entry.message
            }
        }()

        if let last = self.lastCondensedMessage, last == condensedMessage {
            self.duplicateCount += 1
            if self.duplicateCount % self.duplicateSummaryThreshold != 0 {
                return
            } else {
                let summaryEntry = AXLogEntry(
                    level: .debug,
                    message: "⟳ Previous message repeated \(self.duplicateSummaryThreshold) more times",
                    file: entry.file,
                    function: entry.function,
                    line: entry.line,
                    details: nil
                )
                self.logEntries.append(summaryEntry)
            }
        } else {
            if self.duplicateCount >= self.duplicateSummaryThreshold && self.lastCondensedMessage != nil {
                let summaryEntry = AXLogEntry(
                    level: .debug,
                    message: "⟳ Previous message repeated \(self.duplicateCount) times in total",
                    file: entry.file,
                    function: entry.function,
                    line: entry.line,
                    details: nil
                )
                self.logEntries.append(summaryEntry)
            }
            self.lastCondensedMessage = condensedMessage
            self.duplicateCount = 0
        }

        let processedEntry = AXLogEntry(
            level: entry.level,
            message: condensedMessage,
            file: entry.file,
            function: entry.function,
            line: entry.line,
            details: entry.details
        )
        self.logEntries.append(processedEntry)

        if self.isJSONLoggingEnabled {
            do {
                let jsonData = try JSONEncoder().encode(processedEntry)
                if let jsonString = String(data: jsonData, encoding: .utf8) {
                    fputs(jsonString + "\n", stderr)
                }
            } catch {
                fputs("{\\\"error\\\": \\\"Failed to serialize AXLogEntry to JSON: \(error.localizedDescription)\\\"}\n", stderr)
            }
        }
    }

    // MARK: - Log Retrieval
    // Assumes these methods are always called on the main thread.
    public func getEntries() -> [AXLogEntry] {
        return self.logEntries
    }

    public func clearEntries() {
        self.logEntries.removeAll()
        // Optionally log the clear action itself
        // let clearEntry = AXLogEntry(level: .info, message: "GlobalAXLogger log entries cleared.")
        // self.log(clearEntry)
    }
    
    public func getLogsAsStrings(format: AXLogOutputFormat = .text) -> [String] {
        let currentEntries = self.getEntries()
        
        switch format {
        case .json:
            return currentEntries.compactMap { entry in
                do {
                    let jsonData = try JSONEncoder().encode(entry)
                    return String(data: jsonData, encoding: .utf8)
                } catch {
                    return "{\\\"error\\\": \\\"Failed to serialize log entry to JSON: \\(error.localizedDescription)\\\"}"
                }
            }
        case .text:
            return currentEntries.map { $0.formattedForTextLog() }
        }
    }
}

// MARK: - Global Logging Functions (Convenience Wrappers)
// These are synchronous and assume GlobalAXLogger.shared.log is safe to call directly (i.e., from main thread).

public func axDebugLog(_ message: String, details: [String: String]? = nil, file: String = #file, function: String = #function, line: Int = #line) {
    let entry = AXLogEntry(level: .debug, message: message, file: file, function: function, line: line, details: details)
    GlobalAXLogger.shared.log(entry)
}

public func axInfoLog(_ message: String, details: [String: String]? = nil, file: String = #file, function: String = #function, line: Int = #line) {
    let entry = AXLogEntry(level: .info, message: message, file: file, function: function, line: line, details: details)
    GlobalAXLogger.shared.log(entry)
}

public func axWarningLog(_ message: String, details: [String: String]? = nil, file: String = #file, function: String = #function, line: Int = #line) {
    let entry = AXLogEntry(level: .warning, message: message, file: file, function: function, line: line, details: details)
    GlobalAXLogger.shared.log(entry)
}

public func axErrorLog(_ message: String, details: [String: String]? = nil, file: String = #file, function: String = #function, line: Int = #line) {
    let entry = AXLogEntry(level: .error, message: message, file: file, function: function, line: line, details: details)
    GlobalAXLogger.shared.log(entry)
}

public func axFatalLog(_ message: String, details: [String: String]? = nil, file: String = #file, function: String = #function, line: Int = #line) {
    let entry = AXLogEntry(level: .critical, message: message, file: file, function: function, line: line, details: details)
    GlobalAXLogger.shared.log(entry)
}

// MARK: - Global Log Access Functions

public func axGetLogEntries() -> [AXLogEntry] {
    return GlobalAXLogger.shared.getEntries()
}

public func axClearLogs() {
    GlobalAXLogger.shared.clearEntries()
}

public func axGetLogsAsStrings(format: AXLogOutputFormat = .text) -> [String] {
    return GlobalAXLogger.shared.getLogsAsStrings(format: format)
}

// Assuming AXLogEntry and its formattedForTextBasedOutput() method are defined elsewhere
// and compatible with synchronous, main-thread only logging.
