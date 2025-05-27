import Foundation

// MARK: - HandlerResponse Definition

/// Represents the standardized response from AXorcist handlers.
public struct HandlerResponse: Codable, Sendable {
    /// The primary data payload of the response. This can be any `Codable` type,
    /// allowing for flexible data structures depending on the handler.
    public var data: AnyCodable? // Using AnyCodable to wrap potentially diverse data types

    /// An optional error message. If present, indicates that the handler encountered an issue.
    public var error: String?

    /// Initializes a new `HandlerResponse`.
    /// - Parameters:
    ///   - data: The data payload.
    ///   - error: An optional error message.
    public init(data: AnyCodable? = nil, error: String? = nil) {
        self.data = data
        self.error = error
    }
}

// MARK: - Convenience Initializers & Properties

extension HandlerResponse {
    /// A Boolean value indicating whether the response represents a successful operation.
    /// A response is considered successful if `error` is `nil`.
    public var succeeded: Bool {
        return error == nil
    }

    /// A Boolean value indicating whether the response represents a failed operation.
    /// A response is considered failed if `error` is not `nil`.
    public var failed: Bool {
        return error != nil
    }

    /// Convenience initializer for a success response with no specific data.
    public static func success(data: AnyCodable? = nil) -> HandlerResponse {
        return HandlerResponse(data: data, error: nil)
    }

    /// Convenience initializer for a failure response.
    /// - Parameter errorMessage: The error message describing the failure.
    public static func failure(errorMessage: String) -> HandlerResponse {
        return HandlerResponse(data: nil, error: errorMessage)
    }
}

// MARK: - AXResponse Integration

extension HandlerResponse {
    /// Creates a HandlerResponse from an AXResponse
    /// - Parameter axResponse: The AXResponse to convert
    public init(from axResponse: AXResponse) {
        switch axResponse {
        case .success(let payload, _):
            self.init(data: payload, error: nil)
        case .error(let message, _, _):
            self.init(data: nil, error: message)
        }
    }
}

// MARK: - Error Structure for Detailed Errors (Example)

/// A structure for providing detailed error information when simple error messages are insufficient.
///
/// DetailedError provides structured error information that can be encoded into the
/// `data` field of a response when the simple `error` string is not enough to
/// convey all necessary error details.
///
/// ## Topics
///
/// ### Error Properties
/// - ``code``
/// - ``message``
/// - ``underlyingError``
///
/// ### Creating Errors
/// - ``init(code:message:underlyingError:)``
///
/// ## Usage
///
/// ```swift
/// let detailedError = DetailedError(
///     code: 1001,
///     message: "Element not found",
///     underlyingError: "AXUIElementCopyAttributeValue failed"
/// )
/// 
/// let response = HandlerResponse(
///     data: AnyCodable(detailedError),
///     error: "Element lookup failed"
/// )
/// ```
public struct DetailedError: Codable, Sendable {
    /// Numeric error code for categorizing the error type.
    ///
    /// Use consistent error codes across your application to enable
    /// programmatic error handling.
    public let code: Int
    
    /// Human-readable error message describing what went wrong.
    ///
    /// This should be clear and actionable for developers debugging issues.
    public let message: String
    
    /// Additional details about underlying system errors.
    ///
    /// When the error is caused by a lower-level system call or API,
    /// this field can contain the original error message for debugging.
    public let underlyingError: String?

    /// Creates a detailed error with the specified information.
    ///
    /// - Parameters:
    ///   - code: Numeric error code for categorization
    ///   - message: Human-readable error description
    ///   - underlyingError: Optional underlying system error details
    public init(code: Int, message: String, underlyingError: String? = nil) {
        self.code = code
        self.message = message
        self.underlyingError = underlyingError
    }
}
