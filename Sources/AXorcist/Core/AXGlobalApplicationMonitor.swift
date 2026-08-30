import AppKit
import Foundation

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
        for observation in self.readinessObservations.values {
            observation.invalidate()
        }
        self.readinessObservations = [:]
        self.applicationsByIdentity = [:]
        self.onLaunch = nil
        self.onTermination = nil
    }

    private let observeRunningApplications:
        (@escaping @Sendable ([NSRunningApplication]) -> Void) -> NSKeyValueObservation
    private var sessionID: UUID?
    private var runningApplicationsObservation: NSKeyValueObservation?
    private var readinessObservations: [NSRunningApplication: NSKeyValueObservation] = [:]
    // Retain AppKit's semantic application keys: separate wrappers for one process instance
    // compare equal, while a replacement process remains a distinct application identity.
    private var applicationsByIdentity: [NSRunningApplication: pid_t] = [:]
    private var onLaunch: (@MainActor (pid_t) -> Void)?
    private var onTermination: (@MainActor (pid_t) -> Void)?

    private func reconcile(_ runningApplications: [NSRunningApplication], sessionID: UUID) {
        // Workspace membership already identifies running apps. Querying isTerminated
        // for each entry can synchronously block on LaunchServices.
        let currentApplications = runningApplications
            .reduce(into: [NSRunningApplication: pid_t]()) { applications, app in
                let processIdentifier = app.processIdentifier
                if processIdentifier > 0 {
                    applications[app] = processIdentifier
                }
            }
        let changes = Self.lifecycleChanges(
            previous: self.applicationsByIdentity,
            current: currentApplications)
        let removedApplications = self.applicationsByIdentity.keys.filter { currentApplications[$0] == nil }
        let addedApplications = currentApplications.keys.filter { self.applicationsByIdentity[$0] == nil }
        for application in removedApplications {
            self.readinessObservations.removeValue(forKey: application)?.invalidate()
        }
        self.applicationsByIdentity = currentApplications
        for processIdentifier in changes.terminations {
            guard self.sessionID == sessionID else { return }
            self.onTermination?(processIdentifier)
        }
        for application in addedApplications {
            guard self.sessionID == sessionID else { return }
            self.observeReadiness(of: application, sessionID: sessionID)
        }
        for processIdentifier in changes.launches {
            guard self.sessionID == sessionID else { return }
            self.onLaunch?(processIdentifier)
        }
    }

    private func observeReadiness(of application: NSRunningApplication, sessionID: UUID) {
        guard !application.isFinishedLaunching else { return }
        let observation = application.observe(\.isFinishedLaunching, options: [.new]) { [weak self] app, change in
            guard change.newValue == true else { return }
            DispatchQueue.main.async { [weak self] in
                self?.applicationBecameReady(app, sessionID: sessionID)
            }
        }
        self.readinessObservations[application] = observation
        if application.isFinishedLaunching {
            self.applicationBecameReady(application, sessionID: sessionID)
        }
    }

    private func applicationBecameReady(_ application: NSRunningApplication, sessionID: UUID) {
        guard self.sessionID == sessionID,
              let processIdentifier = self.applicationsByIdentity[application],
              let observation = Self.claimReadiness(
                  for: application,
                  activeApplications: Set(self.applicationsByIdentity.keys),
                  observations: &self.readinessObservations)
        else { return }
        observation.invalidate()
        self.onLaunch?(processIdentifier)
    }

    static func claimReadiness<Identity: Hashable, Observation>(
        for identity: Identity,
        activeApplications: Set<Identity>,
        observations: inout [Identity: Observation]) -> Observation?
    {
        guard activeApplications.contains(identity) else { return nil }
        return observations.removeValue(forKey: identity)
    }

    static func lifecycleChanges<Identity: Hashable>(
        previous: [Identity: pid_t],
        current: [Identity: pid_t]) -> (terminations: [pid_t], launches: [pid_t])
    {
        let terminations = previous.compactMap { identity, processIdentifier in
            current[identity] == nil ? processIdentifier : nil
        }.sorted()
        let launches = current.compactMap { identity, processIdentifier in
            previous[identity] == nil ? processIdentifier : nil
        }.sorted()
        return (terminations, launches)
    }
}
