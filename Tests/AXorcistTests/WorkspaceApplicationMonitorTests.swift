import AppKit
import Foundation
import Testing
@testable import AXorcist

@Suite("Workspace application monitor")
@MainActor
struct WorkspaceApplicationMonitorTests {
    @Test(.timeLimit(.minutes(1)))
    func `global watcher registers the deferred initial snapshot once before backoff`() async throws {
        let probe = ApplicationMetadataProbe()
        let application = MonitorApplication(instance: "initial", pid: 42, probe: probe)
        let workspace = MonitorWorkspace(applications: [application])
        let monitor = AXWorkspaceApplicationMonitor(workspace: workspace, runningApplications: \.applications)
        let (attempts, continuation) = AsyncStream<pid_t>.makeStream()
        let registry = MonitorRegistry(attempts: continuation)
        let watcher = NotificationWatcher(
            globalNotification: .focusedUIElementChanged,
            registry: registry,
            applicationMonitor: monitor,
            retrySleep: { _ in try await Task.sleep(for: .seconds(60)) },
            handler: { _, _, _, _ in })
        defer { watcher.stop() }

        try watcher.start()
        #expect(watcher.isActive)
        var iterator = attempts.makeAsyncIterator()
        #expect(await iterator.next() == 42)
        await drainMainQueue()

        #expect(registry.processIdentifiers == [42])
        #expect(monitor.runningProcessIdentifiers == [42])
    }

    @Test
    func `lifecycle delivery never queries termination or reads application metadata inside KVO`() async {
        let probe = ApplicationMetadataProbe()
        let application = MonitorApplication(instance: "first", pid: 42, probe: probe)
        let workspace = MonitorWorkspace(applications: [application])
        let monitor = AXWorkspaceApplicationMonitor(workspace: workspace, runningApplications: \.applications)
        var events: [String] = []

        probe.insideCallback = true
        monitor.start(onLaunch: { events.append("launch:\($0)") }, onTermination: { events.append("terminate:\($0)") })
        probe.insideCallback = false
        await drainMainQueue()
        #expect(monitor.runningProcessIdentifiers == [42])

        probe.insideCallback = true
        workspace.applications = []
        probe.insideCallback = false
        await drainMainQueue()

        #expect(events == ["launch:42", "terminate:42"])
        #expect(monitor.runningProcessIdentifiers.isEmpty)
        #expect(probe.terminationReads == 0)
        #expect(probe.reentrantMetadataReads == 0)
        monitor.stop()
    }

    @Test
    func `queued snapshots preserve intermediate termination and semantic PID reuse`() async {
        let probe = ApplicationMetadataProbe()
        let original = MonitorApplication(instance: "original", pid: 42, probe: probe)
        let equalWrapper = MonitorApplication(instance: "original", pid: 42, probe: probe)
        let replacement = MonitorApplication(instance: "replacement", pid: 42, probe: probe)
        let workspace = MonitorWorkspace(applications: [original])
        let monitor = AXWorkspaceApplicationMonitor(workspace: workspace, runningApplications: \.applications)
        var events: [String] = []
        monitor.start(onLaunch: { events.append("launch:\($0)") }, onTermination: { events.append("terminate:\($0)") })
        workspace.applications = [equalWrapper]
        workspace.applications = []
        workspace.applications = [replacement]
        await drainMainQueue()

        #expect(events == ["launch:42", "terminate:42", "launch:42"])
        #expect(monitor.runningProcessIdentifiers == [42])
        monitor.stop()
    }

    @Test
    func `indexed workspace changes retain unchanged applications and reject invalid PIDs`() async {
        let probe = ApplicationMetadataProbe()
        let original = MonitorApplication(instance: "original", pid: 41, probe: probe)
        let added = MonitorApplication(instance: "added", pid: 42, probe: probe)
        let workspace = MonitorWorkspace(applications: [original])
        let monitor = AXWorkspaceApplicationMonitor(workspace: workspace, runningApplications: \.applications)
        var events: [String] = []
        monitor.start(onLaunch: { events.append("launch:\($0)") }, onTermination: { events.append("terminate:\($0)") })
        let applications = workspace.mutableArrayValue(forKey: #keyPath(MonitorWorkspace.applications))
        applications.add(added)
        applications.add(MonitorApplication(instance: "no-pid", pid: -1, probe: probe))
        applications.add(MonitorApplication(instance: "zero", pid: 0, probe: probe))
        await drainMainQueue()

        #expect(events == ["launch:41", "launch:42"])
        #expect(monitor.runningProcessIdentifiers.sorted() == [41, 42])
        applications.removeObject(at: 0)
        await drainMainQueue()

        #expect(events == ["launch:41", "launch:42", "terminate:41"])
        #expect(monitor.runningProcessIdentifiers == [42])
        monitor.stop()
    }

    @Test
    func `stop and restart reject queued lifecycle snapshots from the previous session`() async {
        let probe = ApplicationMetadataProbe()
        let previous = MonitorApplication(instance: "previous", pid: 41, probe: probe)
        let replacement = MonitorApplication(instance: "replacement", pid: 42, probe: probe)
        let workspace = MonitorWorkspace(applications: [previous])
        let monitor = AXWorkspaceApplicationMonitor(workspace: workspace, runningApplications: \.applications)
        var stoppedEvents: [pid_t] = []
        var currentEvents: [String] = []
        monitor.start(onLaunch: { stoppedEvents.append($0) }, onTermination: { stoppedEvents.append($0) })
        monitor.stop()
        workspace.applications = [replacement]
        monitor.start(
            onLaunch: { currentEvents.append("launch:\($0)") },
            onTermination: { currentEvents.append("terminate:\($0)") })
        await drainMainQueue()

        #expect(stoppedEvents.isEmpty)
        #expect(currentEvents == ["launch:42"])
        #expect(monitor.runningProcessIdentifiers == [42])
        monitor.stop()
    }

    @Test
    func `readiness transition retries once without reentering KVO`() async {
        let probe = ApplicationMetadataProbe()
        let application = MonitorApplication(instance: "slow", pid: 42, ready: false, probe: probe)
        let workspace = MonitorWorkspace(applications: [application])
        let monitor = AXWorkspaceApplicationMonitor(workspace: workspace, runningApplications: \.applications)
        var launches: [pid_t] = []
        var reentrantLaunches = 0
        monitor.start(onLaunch: {
            launches.append($0)
            if probe.insideCallback {
                reentrantLaunches += 1
            }
        }, onTermination: { _ in })
        await drainMainQueue()
        #expect(launches == [42])

        probe.insideCallback = true
        application.finishLaunching()
        application.finishLaunching()
        probe.insideCallback = false
        await drainMainQueue()

        #expect(launches == [42, 42])
        #expect(reentrantLaunches == 0)
        monitor.stop()
    }

    @Test
    func `queued readiness cannot revive an observation after stop and restart`() async {
        let probe = ApplicationMetadataProbe()
        let application = MonitorApplication(instance: "slow", pid: 42, ready: false, probe: probe)
        let workspace = MonitorWorkspace(applications: [application])
        let monitor = AXWorkspaceApplicationMonitor(workspace: workspace, runningApplications: \.applications)
        var oldLaunches: [pid_t] = []
        var newLaunches: [pid_t] = []
        monitor.start(onLaunch: { oldLaunches.append($0) }, onTermination: { _ in })
        await drainMainQueue()
        application.finishLaunching()
        monitor.stop()
        monitor.start(onLaunch: { newLaunches.append($0) }, onTermination: { _ in })
        await drainMainQueue()

        #expect(oldLaunches == [42])
        #expect(newLaunches == [42])
        monitor.stop()
    }

    @Test
    func `termination discards a queued readiness callback`() async {
        let probe = ApplicationMetadataProbe()
        let application = MonitorApplication(instance: "slow", pid: 42, ready: false, probe: probe)
        let workspace = MonitorWorkspace(applications: [application])
        let monitor = AXWorkspaceApplicationMonitor(workspace: workspace, runningApplications: \.applications)
        var events: [String] = []
        monitor.start(onLaunch: { events.append("launch:\($0)") }, onTermination: { events.append("terminate:\($0)") })
        await drainMainQueue()
        workspace.applications = []
        application.finishLaunching()
        await drainMainQueue()

        #expect(events == ["launch:42", "terminate:42"])
        #expect(monitor.runningProcessIdentifiers.isEmpty)
        monitor.stop()
    }

    @Test
    func `stopping from a lifecycle handler prevents remaining callbacks`() async {
        let probe = ApplicationMetadataProbe()
        let workspace = MonitorWorkspace(applications: [
            MonitorApplication(instance: "first", pid: 41, probe: probe),
            MonitorApplication(instance: "second", pid: 42, probe: probe),
        ])
        let monitor = AXWorkspaceApplicationMonitor(workspace: workspace, runningApplications: \.applications)
        var launches: [pid_t] = []
        monitor.start(onLaunch: {
            launches.append($0)
            monitor.stop()
        }, onTermination: { _ in })
        await drainMainQueue()

        #expect(launches == [41])
        #expect(monitor.runningProcessIdentifiers.isEmpty)
    }
}

@MainActor
private func drainMainQueue() async {
    await withCheckedContinuation { continuation in
        DispatchQueue.main.async { continuation.resume() }
    }
}

@MainActor
private final class ApplicationMetadataProbe {
    var insideCallback = false
    var terminationReads = 0
    var reentrantMetadataReads = 0

    func recordRead() {
        if self.insideCallback {
            self.reentrantMetadataReads += 1
        }
    }
}

@MainActor
private final class MonitorRegistry: AXObservationRegistry {
    let attempts: AsyncStream<pid_t>.Continuation
    var processIdentifiers: [pid_t] = []

    init(attempts: AsyncStream<pid_t>.Continuation) {
        self.attempts = attempts
    }

    func subscribeProcess(
        pid: pid_t,
        element: Element?,
        notification: AXNotification,
        handler: @escaping AXNotificationSubscriptionHandler) -> Result<SubscriptionToken, AccessibilityError>
    {
        self.processIdentifiers.append(pid)
        self.attempts.yield(pid)
        return .failure(.observerSetupFailed(details: "Synthetic registration failure"))
    }

    func unsubscribe(token: SubscriptionToken) throws {}
}

@MainActor
private final class MonitorWorkspace: NSObject {
    private var storedApplications: [NSRunningApplication]

    @objc dynamic nonisolated var applications: [NSRunningApplication] {
        get { MainActor.assumeIsolated { self.storedApplications } }
        set { MainActor.assumeIsolated { self.storedApplications = newValue } }
    }

    @MainActor
    init(applications: [NSRunningApplication]) {
        self.storedApplications = applications
        super.init()
    }
}

private final nonisolated class MonitorApplication: NSRunningApplication, @unchecked Sendable {
    private let instance: String
    private let pid: pid_t
    private let probe: ApplicationMetadataProbe
    @MainActor private var ready: Bool

    @MainActor
    init(instance: String, pid: pid_t, ready: Bool = true, probe: ApplicationMetadataProbe) {
        self.instance = instance
        self.pid = pid
        self.ready = ready
        self.probe = probe
        super.init()
    }

    override var processIdentifier: pid_t {
        MainActor.assumeIsolated {
            self.probe.recordRead()
            return self.pid
        }
    }

    override var isTerminated: Bool {
        MainActor.assumeIsolated {
            self.probe.recordRead()
            self.probe.terminationReads += 1
            return false
        }
    }

    override var isFinishedLaunching: Bool {
        MainActor.assumeIsolated {
            self.probe.recordRead()
            return self.ready
        }
    }

    @MainActor
    func finishLaunching() {
        let key = #keyPath(NSRunningApplication.isFinishedLaunching)
        self.willChangeValue(forKey: key)
        self.ready = true
        self.didChangeValue(forKey: key)
    }

    override var hash: Int {
        self.instance.hashValue
    }

    override func isEqual(_ object: Any?) -> Bool {
        (object as? MonitorApplication)?.instance == self.instance
    }
}
