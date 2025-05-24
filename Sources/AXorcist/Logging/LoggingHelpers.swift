import Foundation

// Public log functions that wrap GlobalAXLogger.shared.log
// These are the primary interface for logging from other modules.

public func axDebugLog(_ message: @autoclosure @escaping () -> String, details: [String: String]? = nil, file: String = #file, function: String = #function, line: UInt = #line) {
    let actualMessage = message() // Evaluate the message here
    #if DEBUG // Only log debug messages in DEBUG builds, or if explicitly enabled otherwise
        Task {
            await GlobalAXLogger.shared.log(level: .debug, message: actualMessage, file: file, function: function, line: Int(line), details: details)
        }
    #endif
}

public func axInfoLog(_ message: @autoclosure @escaping () -> String, details: [String: String]? = nil, file: String = #file, function: String = #function, line: UInt = #line) {
    let actualMessage = message() // Evaluate the message here
    Task {
        await GlobalAXLogger.shared.log(level: .info, message: actualMessage, file: file, function: function, line: Int(line), details: details)
    }
}

public func axWarningLog(_ message: @autoclosure @escaping () -> String, details: [String: String]? = nil, file: String = #file, function: String = #function, line: UInt = #line) {
    let actualMessage = message() // Evaluate the message here
    Task {
        await GlobalAXLogger.shared.log(level: .warning, message: actualMessage, file: file, function: function, line: Int(line), details: details)
    }
}

public func axErrorLog(_ message: @autoclosure @escaping () -> String, details: [String: String]? = nil, file: String = #file, function: String = #function, line: UInt = #line) {
    let actualMessage = message() // Evaluate the message here
    Task {
        await GlobalAXLogger.shared.log(level: .error, message: actualMessage, file: file, function: function, line: Int(line), details: details)
    }
}

public func axCriticalLog(_ message: @autoclosure @escaping () -> String, details: [String: String]? = nil, file: String = #file, function: String = #function, line: UInt = #line) {
    let actualMessage = message() // Evaluate the message here
    Task {
        await GlobalAXLogger.shared.log(level: .critical, message: actualMessage, file: file, function: function, line: Int(line), details: details)
    }
}
