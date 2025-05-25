import Foundation

// Public log functions that wrap GlobalAXLogger.shared.log
// These are the primary interface for logging from other modules.

public func axDebugLog(_ message: @autoclosure @escaping () -> String, details: [String: String]? = nil, file: String = #file, function: String = #function, line: UInt = #line) {
    let actualMessage = message() // Evaluate the message here
    #if DEBUG // Only log debug messages in DEBUG builds, or if explicitly enabled otherwise
    Task {
        let entry = AXLogEntry(level: .debug, message: actualMessage, file: file, function: function, line: Int(line), details: details)
        await GlobalAXLogger.shared.log(entry)
    }
    #endif
}

public func axInfoLog(_ message: @autoclosure @escaping () -> String, details: [String: String]? = nil, file: String = #file, function: String = #function, line: UInt = #line) {
    let actualMessage = message() // Evaluate the message here
    Task {
        let entry = AXLogEntry(level: .info, message: actualMessage, file: file, function: function, line: Int(line), details: details)
        await GlobalAXLogger.shared.log(entry)
    }
}

public func axWarningLog(_ message: @autoclosure @escaping () -> String, details: [String: String]? = nil, file: String = #file, function: String = #function, line: UInt = #line) {
    let actualMessage = message() // Evaluate the message here
    Task {
        let entry = AXLogEntry(level: .warning, message: actualMessage, file: file, function: function, line: Int(line), details: details)
        await GlobalAXLogger.shared.log(entry)
    }
}

public func axErrorLog(_ message: @autoclosure @escaping () -> String, details: [String: String]? = nil, file: String = #file, function: String = #function, line: UInt = #line) {
    let actualMessage = message() // Evaluate the message here
    Task {
        let entry = AXLogEntry(level: .error, message: actualMessage, file: file, function: function, line: Int(line), details: details)
        await GlobalAXLogger.shared.log(entry)
    }
}

public func axCriticalLog(_ message: @autoclosure @escaping () -> String, details: [String: String]? = nil, file: String = #file, function: String = #function, line: UInt = #line) {
    let actualMessage = message() // Evaluate the message here
    Task {
        let entry = AXLogEntry(level: .critical, message: actualMessage, file: file, function: function, line: Int(line), details: details)
        await GlobalAXLogger.shared.log(entry)
    }
}
