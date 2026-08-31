import AppKit
import Foundation
import os

@MainActor
protocol AXGlobalApplicationMonitoring: AnyObject, Sendable {
    var runningProcessIdentifiers: [pid_t] { get }

    func start(
        onLaunch: @escaping @MainActor (pid_t) -> Void,
        onTermination: @escaping @MainActor (pid_t) -> Void)
    func stop()
}

/// Event-driven application lifecycle source for global AX notification fan-out.
///
/// Accessibility observers are process scoped. `NSWorkspace` supplies the native
/// lifecycle events needed to attach and detach those observers without polling.
@MainActor
final class AXWorkspaceApplicationMonitor: AXGlobalApplicationMonitoring {
    convenience init() {
        self.init(workspace: NSWorkspace.shared, runningApplications: \.runningApplications)
    }

    init<Workspace: NSObject>(
        workspace: Workspace,
        runningApplications: any KeyPath<Workspace, [NSRunningApplication]> & Sendable)
    {
        self.observeRunningApplications = { handler in
            workspace.observe(runningApplications, options: [.initial]) { workspace, _ in
                // Indexed KVO changes can contain only the changed entries. Capture the full
                // membership snapshot here, without reading any application metadata.
                handler(workspace[keyPath: runningApplications])
            }
        }
    }

    var runningProcessIdentifiers: [pid_t] {
        Array(self.applicationsByIdentity.values)
    }

    func start(
        onLaunch: @escaping @MainActor (pid_t) -> Void,
        onTermination: @escaping @MainActor (pid_t) -> Void)
    {
        guard self.sessionID == nil else { return }
        let sessionID = UUID()
        self.sessionID = sessionID
        self.onLaunch = onLaunch
        self.onTermination = onTermination
        self.runningApplicationsObservation = self.observeRunningApplications { [weak self] applications in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.sessionID == sessionID else { return }
                self.reconcile(applications, sessionID: sessionID)
            }
        }
    }

    func stop() {
        self.sessionID = nil
        self.runningApplicationsObservation?.invalidate()
        self.runningApplicationsObservation = nil
        for request in self.metadataRequests.values {
            request.cancel()
        }
        self.metadataRequests = [:]
        self.applicationsByIdentity = [:]
        self.onLaunch = nil
        self.onTermination = nil
    }

    private let observeRunningApplications:
        (@escaping @Sendable ([NSRunningApplication]) -> Void) -> NSKeyValueObservation
    private var sessionID: UUID?
    private var runningApplicationsObservation: NSKeyValueObservation?
    // Reuse one serial worker across sessions: a blocked read never creates replacement workers.
    private let metadataQueue = DispatchQueue(label: "AXorcist.workspace-application-metadata")
    private var metadataRequests: [NSRunningApplication: AXApplicationMetadataRequest] = [:]
    // Retain AppKit's semantic application keys: separate wrappers for one process instance
    // compare equal, while a replacement process remains a distinct application identity.
    private var applicationsByIdentity: [NSRunningApplication: pid_t] = [:]
    private var onLaunch: (@MainActor (pid_t) -> Void)?
    private var onTermination: (@MainActor (pid_t) -> Void)?

    isolated deinit {
        for request in self.metadataRequests.values {
            request.cancel()
        }
    }

    private func reconcile(_ runningApplications: [NSRunningApplication], sessionID: UUID) {
        // Process every complete snapshot in order, even when an earlier metadata read is blocked.
        // Membership removal invalidates its request before a late PID/readiness result can arrive.
        let currentApplications = Set(runningApplications)
        let removedApplications = self.metadataRequests.keys.filter { !currentApplications.contains($0) }
        var terminations: [pid_t] = []
        for application in removedApplications {
            self.metadataRequests.removeValue(forKey: application)?.cancel()
            if let pid = self.applicationsByIdentity.removeValue(forKey: application) {
                terminations.append(pid)
            }
        }
        for pid in terminations.sorted() {
            guard self.sessionID == sessionID else { return }
            self.onTermination?(pid)
        }
        for application in runningApplications {
            guard self.sessionID == sessionID else { return }
            let request: AXApplicationMetadataRequest
            if let existing = self.metadataRequests[application] {
                request = existing
            } else {
                let requestID = UUID()
                request = AXApplicationMetadataRequest(
                    id: requestID,
                    queue: self.metadataQueue)
                { [weak self] event in
                    guard let self, self.sessionID == sessionID,
                          self.metadataRequests[application]?.id == requestID else { return }
                    self.receive(event, from: application)
                }
                self.metadataRequests[application] = request
            }
            request.refresh(application)
        }
    }

    private func receive(_ event: AXApplicationMetadataRequest.Event, from application: NSRunningApplication) {
        switch event {
        case let .pid(pid):
            guard pid > 0 else {
                if let previous = self.applicationsByIdentity.removeValue(forKey: application) {
                    self.onTermination?(previous)
                }
                return
            }
            let previous = self.applicationsByIdentity.updateValue(pid, forKey: application)
            if previous == nil {
                self.onLaunch?(pid)
            }
        case .ready:
            guard let pid = self.applicationsByIdentity[application] else { return }
            self.onLaunch?(pid)
        }
    }
}

/// AppKit documents NSRunningApplication as thread-safe and the SDK marks it Sendable.
/// Only cancellation/observation ownership uses the lock; native calls always run outside it.
private final nonisolated class AXApplicationMetadataRequest: Sendable {
    enum Event: Sendable {
        case pid(pid_t)
        case ready
    }

    private struct State {
        var cancelled = false
        var readinessStarted = false
        var observation: ReadinessObservation?
    }

    private struct ReadinessObservation: Sendable {
        let id: UUID
        let application: NSRunningApplication
        let token: NSKeyValueObservation

        func invalidate() {
            // Foundation's token does not keep its target alive. Retain the exact wrapper
            // through unregistering, even if ARC ends the lease's lifetime at this call.
            withExtendedLifetime(self.application) {
                self.token.invalidate()
            }
        }
    }

    let id: UUID
    private let queue: DispatchQueue
    private let deliver: @MainActor @Sendable (Event) -> Void
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(
        id: UUID,
        queue: DispatchQueue,
        deliver: @escaping @MainActor @Sendable (Event) -> Void)
    {
        self.id = id
        self.queue = queue
        self.deliver = deliver
    }

    func cancel() {
        let observation = self.state.withLock {
            $0.cancelled = true
            let observation = $0.observation
            $0.observation = nil
            return observation
        }
        // Invalidation can contend with KVO delivery; stop must never join native work.
        self.queue.async { observation?.invalidate() }
    }

    func refresh(_ application: NSRunningApplication) {
        self.queue.async { [self] in
            guard !self.isCancelled else { return }
            let pid = application.processIdentifier
            guard !self.isCancelled else { return }
            self.send(.pid(pid))
            guard pid > 0 else {
                self.resetReadiness()
                return
            }
            let shouldObserve = self.state.withLock {
                guard !$0.cancelled, !$0.readinessStarted else { return false }
                $0.readinessStarted = true
                return true
            }
            if shouldObserve {
                self.observeReadiness(of: application)
            }
        }
    }

    private var isCancelled: Bool {
        self.state.withLock { $0.cancelled }
    }

    private func resetReadiness() {
        let observation = self.state.withLock {
            $0.readinessStarted = false
            let observation = $0.observation
            $0.observation = nil
            return observation
        }
        observation?.invalidate()
    }

    private func observeReadiness(of application: NSRunningApplication) {
        guard !application.isFinishedLaunching, !self.isCancelled else { return }
        let observationID = UUID()
        // Do not request .new: KVO would fetch readiness synchronously on the notifying thread.
        let token = application.observe(\.isFinishedLaunching, options: []) { [weak self] application, _ in
            guard let self else { return }
            self.queue.async { self.checkReadiness(of: application, observationID: observationID) }
        }
        let observation = ReadinessObservation(id: observationID, application: application, token: token)
        let installed = self.state.withLock {
            guard !$0.cancelled else { return false }
            $0.observation = observation
            return true
        }
        guard installed else {
            observation.invalidate()
            return
        }
        self.checkReadiness(of: application, observationID: observationID)
    }

    private func checkReadiness(of application: NSRunningApplication, observationID: UUID) {
        guard self.state.withLock({ !$0.cancelled && $0.observation?.id == observationID }),
              application.isFinishedLaunching else { return }
        let observation = self.state.withLock {
            guard !$0.cancelled, $0.observation?.id == observationID else { return nil as ReadinessObservation? }
            let observation = $0.observation
            $0.observation = nil
            return observation
        }
        guard let observation else { return }
        observation.invalidate()
        self.send(.ready)
    }

    private func send(_ event: Event) {
        DispatchQueue.main.async { [deliver] in deliver(event) }
    }
}
