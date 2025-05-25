//
//  AXError+Extensions.swift
//  AXorcist
//
//  Extends AXError with helpful utilities
//

import ApplicationServices
import Foundation

extension AXError: @retroactive Error {}

extension AXError {
    /// Throws if the AXError is not .success
    @usableFromInline func throwIfError() throws {
        if self != .success {
            throw self
        }
    }

    /// Converts AXError to AccessibilityError with appropriate context
    func toAccessibilityError(context: String? = nil) -> AccessibilityError {
        switch self {
        case .success:
            return .genericError("Unexpected success in error context")
        case .apiDisabled:
            return .apiDisabled
        // case .notAllowedBySecurityPolicy, .notAllowed:
        //     return .notAuthorized(context)
        // TODO: Check available error codes in current SDK
        case .invalidUIElement:
            return .invalidElement
        case .attributeUnsupported:
            return .attributeUnsupported(attribute: context ?? "Unknown attribute", elementDescription: nil)
        case .actionUnsupported:
            return .actionUnsupported(action: context ?? "Unknown action", elementDescription: nil)
        case .noValue:
            return .attributeNotReadable(attribute: context ?? "Attribute has no value", elementDescription: nil)
        case .cannotComplete:
            return .genericError(context ?? "Cannot complete operation")
        default:
            return .unknownAXError(self)
        }
    }
}
