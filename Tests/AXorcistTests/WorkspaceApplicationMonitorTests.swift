import AppKit
import Foundation
import os
import Testing
@testable import AXorcist

@Suite("Workspace application monitor", .timeLimit(.minutes(1)))
@MainActor
struct WorkspaceApplicationMonitorTests {
    @Test(arguments: MetadataRead.initialReads)
    private func `blocked metadata leaves MainActor and stop responsive`(_ read: MetadataRead) async {
        let gate = MetadataGate(read: read)
        let probe = ApplicationMetadataProbe()
        let application = MonitorApplication(instance: "blocked", pid: 42, ready: false, probe: probe, gate: gate)
        let workspace = MonitorWorkspace(applications: [application])
        let monitor = AXWorkspaceApplicationMonitor(workspace: workspace, runningApplications: \.applications)
        var launches: [pid_t] = []
        monitor.start(onLaunch: { launches.append($0) }, onTermination: { _ in })
        await gate.waitUntilEntered()

        // A main-thread getter reports the regression and returns instead of deadlocking the test runner.
        #expect(gate.isBlocked, "The metadata read must still be held while MainActor makes progress")
        monitor.stop()
        #expect(monitor.runningProcessIdentifiers.isEmpty)
        let launchesAtStop = launches
        gate.release()
        workspace.applications = []
        monitor.start(onLaunch: { launches.append($0) }, onTermination: { _ in })
        await workspace.flushMetadata()
        #expect(launches == launchesAtStop)
        monitor.stop()
    }

    @Test(arguments: MetadataRead.initialReads)
    private func `blocked metadata cannot revive the previous session`(_ read: MetadataRead) async {
        let gate = MetadataGate(read: read)
        let probe = ApplicationMetadataProbe()
        let previous = MonitorApplication(instance: "previous", pid: 41, ready: false, probe: probe, gate: gate)
        let replacement = MonitorApplication(instance: "replacement", pid: 42, probe: probe)
        let workspace = MonitorWorkspace(applications: [previous])
        let monitor = AXWorkspaceApplicationMonitor(workspace: workspace, runningApplications: \.applications)
        var oldLaunches: [pid_t] = []
        var newLaunches: [pid_t] = []
        monitor.start(onLaunch: { oldLaunches.append($0) }, onTermination: { _ in })
        await gate.waitUntilEntered()
        monitor.stop()
        let launchesAtStop = oldLaunches
        workspace.applications = [replacement]
        monitor.start(onLaunch: { newLaunches.append($0) }, onTermination: { _ in })
        await drainMainQueue()

        #expect(gate.isBlocked)
        #expect(monitor.runningProcessIdentifiers.isEmpty)
        gate.release()
        await workspace.flushMetadata()
        #expect(oldLaunches == launchesAtStop)
        #expect(newLaunches == [42])
        #expect(monitor.runningProcessIdentifiers == [42])
        monitor.stop()
    }

    @Test(arguments: MetadataRead.initialReads, [false, true])
    private func `blocked metadata cannot escape membership removal`(
        _ read: MetadataRead,
        sameIdentity: Bool) async
    {
        let gate = MetadataGate(read: read)
        let probe = ApplicationMetadataProbe()
        let previous = MonitorApplication(instance: "previous", pid: 42, ready: false, probe: probe, gate: gate)
        let replacement = MonitorApplication(
            instance: sameIdentity ? "previous" : "replacement", pid: 42, ready: false, probe: probe)
        let workspace = MonitorWorkspace(applications: [previous])
        let monitor = AXWorkspaceApplicationMonitor(workspace: workspace, runningApplications: \.applications)
        var events: [String] = []
        monitor.start(onLaunch: { events.append("launch:\($0)") }, onTermination: { events.append("terminate:\($0)") })
        await gate.waitUntilEntered()
        await drainMainQueue()
        let initialEvents = events
        if sameIdentity {
            workspace.applications = []
        }
        workspace.applications = [replacement]
        await drainMainQueue()

        #expect(gate.isBlocked)
        #expect(monitor.runningProcessIdentifiers.isEmpty)
        let removedEvents = initialEvents.isEmpty ? [] : ["launch:42", "terminate:42"]
        #expect(events == removedEvents)
        gate.release()
        await workspace.flushMetadata()
        #expect(events == removedEvents + ["launch:42"])
        previous.finishLaunching()
        previous.finishLaunching()
        await workspace.flushMetadata()
        #expect(events == removedEvents + ["launch:42"])
        replacement.finishLaunching()
        replacement.finishLaunching()
        await workspace.flushMetadata()
        #expect(events == removedEvents + ["launch:42", "launch:42"])
        #expect(monitor.runningProcessIdentifiers == [42])
        monitor.stop()
    }

    @Test(arguments: [MetadataRead.readinessCheck, .readinessRecheck])
    private func `readiness check subscribe recheck closes both transition races`(_ read: MetadataRead) async {
        let gate = MetadataGate(read: read)
        let probe = ApplicationMetadataProbe()
        let application = MonitorApplication(instance: "slow", pid: 42, ready: false, probe: probe, gate: gate)
        let workspace = MonitorWorkspace(applications: [application])
        let monitor = AXWorkspaceApplicationMonitor(workspace: workspace, runningApplications: \.applications)
        var launches: [pid_t] = []
        monitor.start(onLaunch: { launches.append($0) }, onTermination: { _ in })
        await gate.waitUntilEntered()
        probe.insideCallback = true
        application.finishLaunching()
        application.finishLaunching()
        probe.insideCallback = false
        #expect(gate.isBlocked)
        gate.release()
        await workspace.flushMetadata()

        #expect(launches == [42, 42])
        #expect(probe.reentrantMetadataReads == 0)
        monitor.stop()
    }

    @Test
    func `readiness notification defers its blocked getter and stop discards the result`() async {
        let gate = MetadataGate(read: .readinessNotification)
        let probe = ApplicationMetadataProbe()
        let application = MonitorApplication(instance: "slow", pid: 42, ready: false, probe: probe, gate: gate)
        let workspace = MonitorWorkspace(applications: [application])
        let monitor = AXWorkspaceApplicationMonitor(workspace: workspace, runningApplications: \.applications)
        var launches: [pid_t] = []
        monitor.start(onLaunch: { launches.append($0) }, onTermination: { _ in })
        await workspace.flushMetadata()
        probe.insideCallback = true
        application.finishLaunching()
        probe.insideCallback = false
        await gate.waitUntilEntered()

        #expect(gate.isBlocked)
        #expect(probe.reentrantMetadataReads == 0)
        monitor.stop()
        gate.release()
        workspace.applications = []
        monitor.start(onLaunch: { launches.append($0) }, onTermination: { _ in })
        await workspace.flushMetadata()
        #expect(launches == [42])
        #expect(monitor.runningProcessIdentifiers.isEmpty)
        monitor.stop()
    }

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
        await workspace.flushMetadata()

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
        await workspace.flushMetadata()
        #expect(monitor.runningProcessIdentifiers == [42])

        probe.insideCallback = true
        workspace.applications = []
        probe.insideCallback = false
        await workspace.flushMetadata()

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
        await workspace.flushMetadata()
        workspace.applications = [equalWrapper]
        await workspace.flushMetadata()
        #expect(events == ["launch:42"])
        workspace.applications = []
        workspace.applications = [replacement]
        await workspace.flushMetadata()

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
        await workspace.flushMetadata()

        #expect(events == ["launch:41", "launch:42"])
        #expect(monitor.runningProcessIdentifiers.sorted() == [41, 42])
        applications.removeObject(at: 0)
        await workspace.flushMetadata()

        #expect(events == ["launch:41", "launch:42", "terminate:41"])
        #expect(monitor.runningProcessIdentifiers == [42])
        monitor.stop()
    }

    @Test
    func `ordered snapshots preserve positive PID transitions for equal wrappers`() async {
        let probe = ApplicationMetadataProbe()
        let workspace = MonitorWorkspace(applications: [MonitorApplication(instance: "same", pid: -1, probe: probe)])
        let monitor = AXWorkspaceApplicationMonitor(workspace: workspace, runningApplications: \.applications)
        var events: [String] = []
        monitor.start(onLaunch: { events.append("launch:\($0)") }, onTermination: { events.append("terminate:\($0)") })
        workspace.applications = [MonitorApplication(instance: "same", pid: 42, probe: probe)]
        workspace.applications = [MonitorApplication(instance: "same", pid: 0, probe: probe)]
        workspace.applications = [MonitorApplication(instance: "same", pid: 43, probe: probe)]
        await workspace.flushMetadata()

        #expect(events == ["launch:42", "terminate:42", "launch:43"])
        #expect(monitor.runningProcessIdentifiers == [43])
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
        await workspace.flushMetadata()

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
        await workspace.flushMetadata()
        #expect(launches == [42])

        probe.insideCallback = true
        application.finishLaunching()
        application.finishLaunching()
        probe.insideCallback = false
        await workspace.flushMetadata()

        #expect(launches == [42, 42])
        #expect(reentrantLaunches == 0)
        #expect(probe.reentrantMetadataReads == 0)
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
        await workspace.flushMetadata()
        application.finishLaunching()
        monitor.stop()
        monitor.start(onLaunch: { newLaunches.append($0) }, onTermination: { _ in })
        await workspace.flushMetadata()

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
        await workspace.flushMetadata()
        workspace.applications = []
        application.finishLaunching()
        await workspace.flushMetadata()

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
        let stopped = AsyncStream<Void>.makeStream()
        monitor.start(onLaunch: {
            launches.append($0)
            monitor.stop()
            stopped.continuation.yield(())
        }, onTermination: { _ in })
        var iterator = stopped.stream.makeAsyncIterator()
        _ = await iterator.next()
        #expect(monitor.runningProcessIdentifiers.isEmpty)
        workspace.applications = []
        monitor.start(onLaunch: { launches.append($0) }, onTermination: { _ in })
        await workspace.flushMetadata()

        #expect(launches == [41])
        #expect(monitor.runningProcessIdentifiers.isEmpty)
        monitor.stop()
    }
}

@MainActor
extension WorkspaceApplicationMonitorTests {
    @Test(arguments: ObservationEnd.allCases)
    private func `readiness lease retains the exact wrapper through queued invalidation`(_ end: ObservationEnd) async {
        let probe = ApplicationMetadataProbe()
        let lifetime = ApplicationLifetimeProbe()
        let workspace = MonitorWorkspace(applications: [MonitorApplication(instance: "same", pid: 0, probe: probe)])
        var monitor: AXWorkspaceApplicationMonitor? = AXWorkspaceApplicationMonitor(
            workspace: workspace, runningApplications: \.applications)
        monitor?.start(onLaunch: { _ in }, onTermination: { _ in })
        await workspace.flushMetadata()

        // The request's original semantic key is not the wrapper on which KVO is installed.
        let observed = workspace.replaceWithLifetimeApplication(probe: probe, lifetime: lifetime)
        await workspace.flushMetadata()
        #expect(lifetime.registrations == 1)

        let gate = MetadataGate(read: .pid)
        workspace.applications.append(MonitorApplication(instance: "blocker", pid: 43, probe: probe, gate: gate))
        await gate.waitUntilEntered()
        workspace.applications = [MonitorApplication(instance: "same", pid: 42, probe: probe)]
        await drainMainQueue()
        #expect(observed.value != nil, "Semantic wrapper churn must retain the exact KVO target")

        switch end {
        case .removal:
            workspace.applications = []
            await drainMainQueue()
        case .stop:
            monitor?.stop()
            workspace.applications = []
        case .destruction:
            monitor = nil
            workspace.applications = []
        }
        #expect(gate.isBlocked)
        #expect(
            observed.value != nil,
            "Queued invalidation must own the observed wrapper until unregistering completes")
        #expect(lifetime.removals == 0)
        gate.release()
        await lifetime.waitForDeallocation()
        #expect(observed.value == nil)
        #expect(lifetime.removals == 1)
        #expect(!lifetime.deallocatedWhileObserved)
        monitor?.stop()
    }

    @Test(arguments: ObservationInvalidation.allCases)
    private func `readiness lease survives invalidation completion and installation cancellation`(
        _ invalidation: ObservationInvalidation) async
    {
        let probe = ApplicationMetadataProbe()
        let installation = ObservationGate()
        let removal = ObservationGate()
        let lifetime = ApplicationLifetimeProbe(
            afterRegistration: {
                if invalidation == .cancelledInstallation {
                    installation.hold()
                }
            },
            beforeRemovalReturns: { removal.hold() })
        let workspace = MonitorWorkspace(applications: [MonitorApplication(instance: "same", pid: 0, probe: probe)])
        let monitor = AXWorkspaceApplicationMonitor(workspace: workspace, runningApplications: \.applications)
        var launches: [pid_t] = []
        monitor.start(onLaunch: { launches.append($0) }, onTermination: { _ in })
        await workspace.flushMetadata()
        let observed = workspace.replaceWithLifetimeApplication(probe: probe, lifetime: lifetime)

        if invalidation == .cancelledInstallation {
            await installation.waitUntilEntered()
            monitor.stop()
            workspace.applications = []
            #expect(observed.value != nil)
            installation.release()
        } else {
            await workspace.flushMetadata()
            workspace.applications = [MonitorApplication(
                instance: "same", pid: invalidation == .reset ? 0 : 42, probe: probe)]
            if invalidation == .readiness {
                observed.value?.finishLaunching()
            }
        }
        await removal.waitUntilEntered()
        monitor.stop()
        workspace.applications = []
        let launchesAtStop = launches
        #expect(observed.value != nil, "The exact target must survive until invalidate returns")
        #expect(lifetime.removals == 0)
        #expect(monitor.runningProcessIdentifiers.isEmpty)
        removal.release()
        await lifetime.waitForDeallocation()
        #expect(observed.value == nil)
        #expect(lifetime.removals == 1)
        #expect(!lifetime.deallocatedWhileObserved)
        monitor.start(onLaunch: { launches.append($0) }, onTermination: { _ in })
        await workspace.flushMetadata()
        #expect(launches == launchesAtStop)
        monitor.stop()
    }
}

@MainActor
private func drainMainQueue() async {
    await withCheckedContinuation { continuation in
        DispatchQueue.main.async { continuation.resume() }
    }
}

private final nonisolated class ApplicationMetadataProbe: Sendable {
    private struct State {
        var insideCallback = false
        var terminationReads = 0
        var reentrantMetadataReads = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    var insideCallback: Bool {
        get { self.state.withLock { $0.insideCallback } }
        set { self.state.withLock { $0.insideCallback = newValue } }
    }

    var terminationReads: Int {
        self.state.withLock { $0.terminationReads }
    }

    var reentrantMetadataReads: Int {
        self.state.withLock { $0.reentrantMetadataReads }
    }

    func recordRead(termination: Bool = false) {
        self.state.withLock {
            // The synthetic KVO setters run on MainActor; concurrent background reads are allowed.
            if $0.insideCallback, Thread.isMainThread {
                $0.reentrantMetadataReads += 1
            }
            if termination {
                $0.terminationReads += 1
            }
        }
    }
}

private nonisolated enum MetadataRead: Sendable {
    case pid, readinessCheck, readinessRecheck, readinessNotification

    static let initialReads: [Self] = [.pid, .readinessCheck, .readinessRecheck]
}

private nonisolated enum ObservationEnd: CaseIterable, Sendable {
    case removal, stop, destruction
}

private nonisolated enum ObservationInvalidation: CaseIterable, Sendable {
    case reset, readiness, cancelledInstallation
}

private final nonisolated class ObservationGate: Sendable {
    private let entry = AsyncStream<Void>.makeStream()
    private let semaphore = DispatchSemaphore(value: 0)

    func hold() {
        #expect(!Thread.isMainThread)
        self.entry.continuation.yield(())
        if !Thread.isMainThread {
            self.semaphore.wait()
        }
    }

    func waitUntilEntered() async {
        var iterator = self.entry.stream.makeAsyncIterator()
        _ = await iterator.next()
    }

    func release() {
        self.semaphore.signal()
    }
}

private final nonisolated class ApplicationLifetimeProbe: Sendable {
    private struct State {
        var registrations = 0
        var removals = 0
        var deallocatedWhileObserved = false
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let deallocation = AsyncStream<Void>.makeStream()
    private let afterRegistration: (@Sendable () -> Void)?
    private let beforeRemovalReturns: (@Sendable () -> Void)?

    init(afterRegistration: (@Sendable () -> Void)? = nil, beforeRemovalReturns: (@Sendable () -> Void)? = nil) {
        self.afterRegistration = afterRegistration
        self.beforeRemovalReturns = beforeRemovalReturns
    }

    var registrations: Int {
        self.state.withLock { $0.registrations }
    }

    var removals: Int {
        self.state.withLock { $0.removals }
    }

    var deallocatedWhileObserved: Bool {
        self.state.withLock { $0.deallocatedWhileObserved }
    }

    func registered() {
        #expect(!Thread.isMainThread)
        self.state.withLock { $0.registrations += 1 }
        self.afterRegistration?()
    }

    func removed() {
        #expect(!Thread.isMainThread)
        self.beforeRemovalReturns?()
        self.state.withLock { $0.removals += 1 }
    }

    func deallocated() {
        self.state.withLock { $0.deallocatedWhileObserved = $0.registrations > $0.removals }
        self.deallocation.continuation.yield(())
    }

    func waitForDeallocation() async {
        var iterator = self.deallocation.stream.makeAsyncIterator()
        _ = await iterator.next()
    }
}

private final nonisolated class MetadataGate: Sendable {
    private struct State {
        var readinessReads = 0
        var entered = false
        var blocked = false
    }

    private let read: MetadataRead
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let semaphore = DispatchSemaphore(value: 0)
    private let entry = AsyncStream<Void>.makeStream()

    init(read: MetadataRead) {
        self.read = read
    }

    var isBlocked: Bool {
        self.state.withLock { $0.blocked }
    }

    func visit(pid: Bool) {
        let shouldBlock = self.state.withLock { state in
            if !pid {
                state.readinessReads += 1
            }
            let matches = switch self.read {
            case .pid: pid
            case .readinessCheck: !pid && state.readinessReads == 1
            case .readinessRecheck: !pid && state.readinessReads == 2
            case .readinessNotification: !pid && state.readinessReads == 3
            }
            guard matches, !state.entered else { return false }
            state.entered = true
            state.blocked = !Thread.isMainThread
            return true
        }
        guard shouldBlock else { return }
        #expect(!Thread.isMainThread, "Blocking application metadata was read on the main thread")
        self.entry.continuation.yield(())
        guard !Thread.isMainThread else { return }
        self.semaphore.wait()
        self.state.withLock { $0.blocked = false }
    }

    func waitUntilEntered() async {
        var iterator = self.entry.stream.makeAsyncIterator()
        _ = await iterator.next()
    }

    func release() {
        self.semaphore.signal()
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

    func replaceWithLifetimeApplication(
        probe: ApplicationMetadataProbe,
        lifetime: ApplicationLifetimeProbe) -> WeakMonitorApplication
    {
        autoreleasepool {
            let application = MonitorApplication(
                instance: "same",
                pid: 42,
                ready: false,
                probe: probe,
                lifetime: lifetime)
            self.applications = [application]
            return WeakMonitorApplication(application)
        }
    }

    /// A synthetic invalid-PID member is an observable fence behind earlier metadata work.
    /// No production queue/test hook or timing assumption is needed.
    func flushMetadata() async {
        await drainMainQueue()
        let read = AsyncStream<Void>.makeStream()
        let fence = MonitorApplication(instance: UUID().uuidString, pid: -1, probe: ApplicationMetadataProbe()) {
            DispatchQueue.main.async { read.continuation.yield(()) }
        }
        self.applications.append(fence)
        var iterator = read.stream.makeAsyncIterator()
        _ = await iterator.next()
        self.applications.removeAll { $0 === fence }
        await drainMainQueue()
    }
}

@MainActor
private final class WeakMonitorApplication {
    weak var value: MonitorApplication?

    init(_ application: MonitorApplication) {
        self.value = application
    }
}

private final nonisolated class MonitorApplication: NSRunningApplication, @unchecked Sendable {
    // Foundation may try to unregister during super.deinit, after Swift stored properties are gone.
    // Keep the baseline regression an assertion failure instead of calling AppKit on that dead state.
    private static let deallocating = OSAllocatedUnfairLock(initialState: Set<ObjectIdentifier>())
    private let instance: String
    private let pid: pid_t
    private let probe: ApplicationMetadataProbe
    private let ready: OSAllocatedUnfairLock<Bool>
    private let gate: MetadataGate?
    private let lifetime: ApplicationLifetimeProbe?
    private let onPIDRead: (@Sendable () -> Void)?

    @MainActor
    init(
        instance: String,
        pid: pid_t,
        ready: Bool = true,
        probe: ApplicationMetadataProbe,
        gate: MetadataGate? = nil,
        lifetime: ApplicationLifetimeProbe? = nil,
        onPIDRead: (@Sendable () -> Void)? = nil)
    {
        self.instance = instance
        self.pid = pid
        self.ready = OSAllocatedUnfairLock(initialState: ready)
        self.probe = probe
        self.gate = gate
        self.lifetime = lifetime
        self.onPIDRead = onPIDRead
        super.init()
        _ = Self.deallocating.withLock { $0.remove(ObjectIdentifier(self)) }
    }

    deinit {
        if let lifetime = self.lifetime {
            _ = Self.deallocating.withLock { $0.insert(ObjectIdentifier(self)) }
            lifetime.deallocated()
        }
    }

    override func addObserver(
        _ observer: NSObject,
        forKeyPath keyPath: String,
        options: NSKeyValueObservingOptions = [],
        context: UnsafeMutableRawPointer?)
    {
        super.addObserver(observer, forKeyPath: keyPath, options: options, context: context)
        self.lifetime?.registered()
    }

    override func removeObserver(_ observer: NSObject, forKeyPath keyPath: String, context: UnsafeMutableRawPointer?) {
        guard !Self.deallocating.withLock({ $0.contains(ObjectIdentifier(self)) }) else { return }
        super.removeObserver(observer, forKeyPath: keyPath, context: context)
        self.lifetime?.removed()
    }

    override var processIdentifier: pid_t {
        self.probe.recordRead()
        self.gate?.visit(pid: true)
        self.onPIDRead?()
        return self.pid
    }

    override var isTerminated: Bool {
        self.probe.recordRead(termination: true)
        return false
    }

    override var isFinishedLaunching: Bool {
        self.probe.recordRead()
        let ready = self.ready.withLock { $0 }
        self.gate?.visit(pid: false)
        return ready
    }

    @MainActor
    func finishLaunching() {
        let key = #keyPath(NSRunningApplication.isFinishedLaunching)
        self.willChangeValue(forKey: key)
        self.ready.withLock { $0 = true }
        self.didChangeValue(forKey: key)
    }

    override var hash: Int {
        self.instance.hashValue
    }

    override func isEqual(_ object: Any?) -> Bool {
        (object as? MonitorApplication)?.instance == self.instance
    }
}
