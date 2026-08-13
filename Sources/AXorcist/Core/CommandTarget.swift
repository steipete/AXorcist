import ApplicationServices
import Foundation

enum AXApplicationTarget: Equatable, Sendable {
    case focused
    case identifier(String)
    case process(pid_t)

    init(appIdentifier: String?, pid: Int?) throws {
        if let appIdentifier, let pid {
            throw AXCommandTargetError.conflictingSelectors(application: appIdentifier, pid: pid)
        }

        if let pid {
            guard pid > 0, pid <= Int(pid_t.max) else {
                throw AXCommandTargetError.invalidProcessIdentifier(pid)
            }
            self = .process(pid_t(pid))
            return
        }

        guard let appIdentifier else {
            self = .focused
            return
        }
        guard !appIdentifier.isEmpty else {
            throw AXCommandTargetError.emptyApplicationIdentifier
        }
        self = appIdentifier == "focused" ? .focused : .identifier(appIdentifier)
    }

    var description: String {
        switch self {
        case .focused:
            "focused application"
        case let .identifier(identifier):
            "application '\(identifier)'"
        case let .process(pid):
            "process \(pid)"
        }
    }

    var lookupIdentifier: String {
        switch self {
        case .focused:
            "focused"
        case let .identifier(identifier):
            identifier
        case let .process(pid):
            String(pid)
        }
    }
}

enum AXCommandTargetError: Error, Equatable {
    case conflictingSelectors(application: String, pid: Int)
    case emptyApplicationIdentifier
    case invalidProcessIdentifier(Int)
    case applicationNotFound(String)
    case elementNotFound(String)

    var responseCode: AXErrorCode {
        switch self {
        case .conflictingSelectors, .emptyApplicationIdentifier, .invalidProcessIdentifier:
            .invalidParameter
        case .applicationNotFound:
            .applicationNotFound
        case .elementNotFound:
            .elementNotFound
        }
    }

    var message: String {
        switch self {
        case let .conflictingSelectors(application, pid):
            "Specify either application '\(application)' or PID \(pid), not both."
        case .emptyApplicationIdentifier:
            "Application identifier must not be empty."
        case let .invalidProcessIdentifier(pid):
            "PID must be between 1 and \(pid_t.max); received \(pid)."
        case let .applicationNotFound(target), let .elementNotFound(target):
            target
        }
    }

    @MainActor var response: AXResponse {
        .errorResponse(message: self.message, code: self.responseCode)
    }
}

struct AXResolvedApplicationTarget {
    let target: AXApplicationTarget
    let element: Element
}

typealias AXApplicationElementResolver = @MainActor (AXApplicationTarget) -> Element?

@MainActor
func nativeApplicationElement(for target: AXApplicationTarget) -> Element? {
    switch target {
    case .focused:
        getApplicationElement(for: "focused")
    case let .identifier(identifier):
        getApplicationElement(for: identifier)
    case let .process(pid):
        Element.application(for: pid)
    }
}

@MainActor
func resolveApplicationTarget(
    appIdentifier: String?,
    pid: Int?,
    using resolver: AXApplicationElementResolver = nativeApplicationElement)
    -> Result<AXResolvedApplicationTarget, AXCommandTargetError>
{
    let target: AXApplicationTarget
    do {
        target = try AXApplicationTarget(appIdentifier: appIdentifier, pid: pid)
    } catch let error as AXCommandTargetError {
        return .failure(error)
    } catch {
        return .failure(.applicationNotFound("Unable to resolve application target."))
    }

    guard let element = resolver(target) else {
        return .failure(.applicationNotFound("Could not resolve \(target.description)."))
    }
    return .success(AXResolvedApplicationTarget(target: target, element: element))
}

@MainActor
func resolveTargetElement(
    appIdentifier: String?,
    pid: Int?,
    locator: Locator,
    maxDepthForSearch: Int,
    using resolver: AXApplicationElementResolver = nativeApplicationElement)
    -> Result<Element, AXCommandTargetError>
{
    switch resolveApplicationTarget(appIdentifier: appIdentifier, pid: pid, using: resolver) {
    case let .failure(error):
        return .failure(error)
    case let .success(resolvedTarget):
        let result = findTargetElement(
            startingFrom: resolvedTarget.element,
            targetDescription: resolvedTarget.target.description,
            locator: locator,
            maxDepthForSearch: maxDepthForSearch)
        guard let element = result.element else {
            return .failure(.elementNotFound(
                result.error ?? "Element not found in \(resolvedTarget.target.description)."))
        }
        return .success(element)
    }
}
