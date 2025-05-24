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

// MARK: - Error Structure for Detailed Errors (Example)

/// An example structure for providing more detailed error information if needed.
/// This can be encoded into the `data` field if `error` alone is insufficient.
public struct DetailedError: Codable, Sendable {
    public let code: Int
    public let message: String
    public let underlyingError: String?

    public init(code: Int, message: String, underlyingError: String? = nil) {
        self.code = code
        self.message = message
        self.underlyingError = underlyingError
    }
}
