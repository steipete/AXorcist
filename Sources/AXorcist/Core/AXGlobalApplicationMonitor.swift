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
    var runningProcessIdentifiers: [pid_t] {
        Self.eligibleApplications(NSWorkspace.shared.runningApplications).map(\.processIdentifier)
    }

    func start(
        onLaunch: @escaping @MainActor (pid_t) -> Void,
        onTermination: @escaping @MainActor (pid_t) -> Void)
    {
        guard self.runningApplicationsObservation == nil else { return }
        self.onLaunch = onLaunch
        self.onTermination = onTermination
        self.runningApplicationsObservation = NSWorkspace.shared.observe(
            \.runningApplications,
            options: [.initial, .new])
        { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.reconcile(NSWorkspace.shared.runningApplications)
            }
        }
    }

    func stop() {
        self.runningApplicationsObservation?.invalidate()
        self.runningApplicationsObservation = nil
        self.applicationsByIdentity = [:]
        self.onLaunch = nil
        self.onTermination = nil
    }

    private var runningApplicationsObservation: NSKeyValueObservation?
    // Retain AppKit's semantic application keys: separate wrappers for one process instance
    // compare equal, while a replacement process remains a distinct application identity.
    private var applicationsByIdentity: [NSRunningApplication: pid_t] = [:]
    private var onLaunch: (@MainActor (pid_t) -> Void)?
    private var onTermination: (@MainActor (pid_t) -> Void)?

    private func reconcile(_ runningApplications: [NSRunningApplication]) {
        let currentApplications = Dictionary(
            uniqueKeysWithValues: Self.eligibleApplications(runningApplications).map {
                ($0, $0.processIdentifier)
            })
        let changes = Self.lifecycleChanges(
            previous: self.applicationsByIdentity,
            current: currentApplications)
        for processIdentifier in changes.terminations {
            self.onTermination?(processIdentifier)
        }
        for processIdentifier in changes.launches {
            self.onLaunch?(processIdentifier)
        }
        self.applicationsByIdentity = currentApplications
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

    private static func eligibleApplications(
        _ runningApplications: [NSRunningApplication]) -> [NSRunningApplication]
    {
        runningApplications.filter { !$0.isTerminated && $0.processIdentifier > 0 }
    }
}
