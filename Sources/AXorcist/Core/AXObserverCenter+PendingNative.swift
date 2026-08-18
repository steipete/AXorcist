import ApplicationServices
import Foundation

@MainActor
extension AXObserverCenter {
    func setupRegistrationSynchronously(
        _ registration: AXObserverRegistrationKey,
        expectedGeneration: UInt64,
        expectedEpoch: ObserverStateEpoch) -> Result<Void, AXObserverSubscriptionError>
    {
        if self.nativeRegistrationStates[registration]?.processGeneration == expectedGeneration {
            return .success(())
        }
        if self.observerSetupOverride != nil {
            let error = self.setupOverriddenObserver(registration, expectedGeneration: expectedGeneration)
            return error == .success
                ? .success(())
                : .failure(.nativeRegistrationFailed(
                    registration.subscription.pid,
                    registration.subscription.notification,
                    error))
        }
        guard self.pendingRemovals[registration] == nil else {
            return .failure(.nativeRegistrationFailed(
                registration.subscription.pid,
                registration.subscription.notification,
                .cannotComplete))
        }
        var waiterAlreadyParked = false
        if self.pendingRegistrations[registration] == nil {
            guard let observer = self.getOrCreateObserver(
                for: registration.subscription.pid,
                expectedGeneration: expectedGeneration)
            else {
                return .failure(.observerCreationFailed(registration.subscription.pid))
            }
            _ = self.launchPendingRegistration(
                registration,
                expectedGeneration: expectedGeneration,
                observer: observer,
                parkSynchronousWaiter: true)
            waiterAlreadyParked = true
        }
        let error = self.finishPendingRegistrationSynchronously(
            registration,
            expectedGeneration: expectedGeneration,
            expectedEpoch: expectedEpoch,
            waiterAlreadyParked: waiterAlreadyParked) ?? .cannotComplete
        return error == .success
            ? .success(())
            : .failure(.nativeRegistrationFailed(
                registration.subscription.pid,
                registration.subscription.notification,
                error))
    }

    func setupRegistrationAsync(
        _ registration: AXObserverRegistrationKey,
        expectedGeneration: UInt64) async -> NativeRegistrationSetupResult
    {
        if self.pendingRemovals[registration] != nil {
            return NativeRegistrationSetupResult(error: .cannotComplete, state: nil)
        }
        if let pending = self.pendingRegistrations[registration] {
            guard pending.expectedGeneration == expectedGeneration else {
                return NativeRegistrationSetupResult(error: .cannotComplete, state: nil)
            }
            _ = await pending.completion.value()
            if let stored = pending.completion.currentResult() {
                return NativeRegistrationSetupResult(
                    error: stored.error,
                    state: self.nativeRegistrationStates[registration])
            }
            return NativeRegistrationSetupResult(error: .cannotComplete, state: nil)
        }
        guard let observer = await self.getOrCreateObserverAsync(
            for: registration.subscription.pid,
            expectedGeneration: expectedGeneration)
        else {
            return NativeRegistrationSetupResult(error: .failure, state: nil)
        }
        let pending = self.launchPendingRegistration(
            registration,
            expectedGeneration: expectedGeneration,
            observer: observer,
            parkSynchronousWaiter: false)
        return await pending.task.value
    }

    private func launchPendingRegistration(
        _ registration: AXObserverRegistrationKey,
        expectedGeneration: UInt64,
        observer: AXObserver,
        parkSynchronousWaiter: Bool) -> PendingRegistration
    {
        if let pending = self.pendingRegistrations[registration] {
            return pending
        }
        let launch = PendingAddLaunch(
            id: UUID(),
            expectedGeneration: expectedGeneration,
            completion: NativeAddCompletion(),
            work: self.nativeRegistrationWork(for: registration, observer: observer),
            startGate: ObserverAsyncStartGate())
        let task = self.makePendingRegistrationTask(registration, launch: launch)
        let pending = PendingRegistration(
            id: launch.id,
            expectedGeneration: expectedGeneration,
            task: task,
            completion: launch.completion,
            work: launch.work)
        self.pendingRegistrations[registration] = pending
        if parkSynchronousWaiter {
            _ = launch.completion.beginSynchronousWait()
        }
        launch.startGate.open()
        return pending
    }

    private func makePendingRegistrationTask(
        _ registration: AXObserverRegistrationKey,
        launch: PendingAddLaunch) -> Task<NativeRegistrationSetupResult, Never>
    {
        let nativeWorkAdmission = self.nativeWorkAdmission
        return Task.detached(priority: .utility) { [weak self] in
            await launch.startGate.wait()
            guard let self else {
                return NativeRegistrationSetupResult(error: .cannotComplete, state: nil)
            }
            let first = await ObserverNativeWork.runPendingAdd(
                admission: nativeWorkAdmission,
                operation: launch.work.add)
            { [weak self] nativeError in
                let outcome = ObserverNativeWork.PendingNativeFirstResult(
                    error: nativeError,
                    timedOut: true)
                if launch.completion.finishNative(with: outcome) == .asynchronous {
                    Task.detached(priority: .utility) { [weak self] in
                        let finalGeneration = await ObserverNativeWork.boundedProcessUniqueIdentity(
                            registration.subscription.pid,
                            admission: nativeWorkAdmission)
                        await self?.resolveLaunchedPendingAdd(
                            registration,
                            launch: launch,
                            outcome: outcome,
                            finalGeneration: finalGeneration)
                    }
                }
            }
            if !first.timedOut {
                if launch.completion.finishNative(with: first) == .asynchronous {
                    let finalGeneration = await ObserverNativeWork.boundedProcessUniqueIdentity(
                        registration.subscription.pid,
                        admission: nativeWorkAdmission)
                    await self.resolveLaunchedPendingAdd(
                        registration,
                        launch: launch,
                        outcome: first,
                        finalGeneration: finalGeneration)
                }
            }
            return await self.registrationSetupResult(
                registration,
                expectedGeneration: launch.expectedGeneration,
                completion: launch.completion,
                fallbackError: first.error)
        }
    }

    func registrationSetupResult(
        _ registration: AXObserverRegistrationKey,
        expectedGeneration: UInt64,
        completion: NativeAddCompletion,
        fallbackError: AXError) -> NativeRegistrationSetupResult
    {
        if let resolved = completion.currentResult(), resolved.error != .success {
            return NativeRegistrationSetupResult(error: resolved.error, state: nil)
        }
        if let state = self.nativeRegistrationStates[registration],
           state.processGeneration == expectedGeneration,
           self.pendingRemovals[registration] == nil
        {
            return NativeRegistrationSetupResult(error: .success, state: state)
        }
        if let resolved = completion.currentResult() {
            return NativeRegistrationSetupResult(
                error: resolved.error == .success ? .cannotComplete : resolved.error,
                state: nil)
        }
        return NativeRegistrationSetupResult(error: fallbackError, state: nil)
    }

    private func resolveLaunchedPendingAdd(
        _ registration: AXObserverRegistrationKey,
        launch: PendingAddLaunch,
        outcome: ObserverNativeWork.PendingNativeFirstResult,
        finalGeneration: UInt64?)
    {
        guard launch.completion.beginAsynchronousResolution() else { return }
        self.completePendingAdd(
            registration,
            resolution: PendingAddResolution(
                operationID: launch.id,
                expectedGeneration: launch.expectedGeneration,
                cleanup: launch.work,
                outcome: outcome,
                finalGeneration: finalGeneration,
                hasSynchronousWaiter: false))
        let resolved = self.resolvedPendingAddOutcome(
            registration,
            operationID: launch.id,
            expectedGeneration: launch.expectedGeneration,
            nativeOutcome: outcome)
        launch.completion.publishResolved(resolved)
    }

    func finishPendingRegistrationSynchronously(
        _ registration: AXObserverRegistrationKey,
        expectedGeneration: UInt64,
        expectedEpoch: ObserverStateEpoch,
        waiterAlreadyParked: Bool = false) -> AXError?
    {
        guard let pending = self.pendingRegistrations[registration] else { return nil }
        guard pending.expectedGeneration == expectedGeneration else { return .cannotComplete }
        let ownsResolution = waiterAlreadyParked || pending.completion.beginSynchronousWait()
        guard ownsResolution else {
            return pending.completion.currentResult()?.error ?? .cannotComplete
        }
        let clock = ContinuousClock()
        guard let nativeOutcome = pending.completion.waitForNativeResult(
            until: clock.now.advanced(by: .seconds(2)))
        else {
            return .cannotComplete
        }
        self.completePendingAdd(
            registration,
            resolution: PendingAddResolution(
                operationID: pending.id,
                expectedGeneration: expectedGeneration,
                cleanup: pending.work,
                outcome: nativeOutcome,
                finalGeneration: self.processIdentityProvider(registration.subscription.pid),
                hasSynchronousWaiter: true))
        let outcome = self.resolvedPendingAddOutcome(
            registration,
            operationID: pending.id,
            expectedGeneration: expectedGeneration,
            nativeOutcome: nativeOutcome)
        pending.completion.publishResolved(outcome)
        let expectedState = NativeRegistrationState(
            operationID: pending.id,
            processGeneration: expectedGeneration)
        let alreadyCommitted = self.nativeRegistrationStates[registration] == expectedState
        guard self.currentStateEpoch(for: registration.subscription.pid) == expectedEpoch else {
            return .cannotComplete
        }
        if outcome.error == .success {
            guard self.observerGenerations[registration.subscription.pid]?.startIdentity == expectedGeneration else {
                return .cannotComplete
            }
            guard alreadyCommitted else { return .cannotComplete }
        }
        return outcome.error
    }

    private func resolvedPendingAddOutcome(
        _ registration: AXObserverRegistrationKey,
        operationID: UUID,
        expectedGeneration: UInt64,
        nativeOutcome: ObserverNativeWork.PendingNativeFirstResult) -> ObserverNativeWork.PendingNativeFirstResult
    {
        guard nativeOutcome.error == .success else { return nativeOutcome }
        let expectedState = NativeRegistrationState(
            operationID: operationID,
            processGeneration: expectedGeneration)
        guard self.nativeRegistrationStates[registration] == expectedState else {
            return ObserverNativeWork.PendingNativeFirstResult(
                error: .cannotComplete,
                timedOut: nativeOutcome.timedOut)
        }
        return nativeOutcome
    }

    func completePendingAdd(
        _ registration: AXObserverRegistrationKey,
        resolution: PendingAddResolution)
    {
        let expectedState = NativeRegistrationState(
            operationID: resolution.operationID,
            processGeneration: resolution.expectedGeneration)
        if self.nativeRegistrationStates[registration] == expectedState {
            return
        }
        let pending = self.pendingRegistrations[registration]
        let stillPending = pending?.id == resolution.operationID
        let waiterCount = stillPending
            ? (pending?.completion.resolutionWaiterCount ?? 0) + (resolution.hasSynchronousWaiter ? 1 : 0)
            : 0
        let generationMatches = resolution.finalGeneration == resolution.expectedGeneration
        let disposition = ObserverNativeWork.pendingAddDisposition(
            nativeError: resolution.outcome.error,
            stillPending: stillPending,
            waiterCount: waiterCount,
            generationMatches: generationMatches,
            isLate: resolution.outcome.timedOut)

        self.logObserverAddResult(
            targetPid: registration.subscription.pid,
            notification: registration.subscription.notification,
            error: resolution.outcome.error)

        switch disposition {
        case .commit:
            self.nativeRegistrationStates[registration] = NativeRegistrationState(
                operationID: resolution.operationID,
                processGeneration: resolution.expectedGeneration)
            if stillPending {
                self.pendingRegistrations.removeValue(forKey: registration)
            }
        case .pendingRemoval:
            self.completePendingAddRemoval(
                registration,
                resolution: resolution,
                stillPending: stillPending)
        case .finishOnly:
            if stillPending {
                self.pendingRegistrations.removeValue(forKey: registration)
            }
            self.removeObserverIfUnused(targetPid: registration.subscription.pid)
        }
    }

    private func completePendingAddRemoval(
        _ registration: AXObserverRegistrationKey,
        resolution: PendingAddResolution,
        stillPending: Bool)
    {
        if stillPending {
            self.pendingRegistrations.removeValue(forKey: registration)
        }
        if ObserverNativeWork.shouldResetObserverGeneration(
            observed: resolution.finalGeneration,
            expected: resolution.expectedGeneration)
        {
            self.resetObserverGeneration(
                for: registration.subscription.pid,
                ifMatching: resolution.expectedGeneration)
        }
        if stillPending || self.shouldScheduleUnownedLateRemoval(registration) {
            self.scheduleNativeRemoval(registration, cleanup: resolution.cleanup)
        }
    }

    func shouldScheduleUnownedLateRemoval(_ registration: AXObserverRegistrationKey) -> Bool {
        self.pendingRegistrations[registration] == nil
            && self.nativeRegistrationStates[registration] == nil
            && self.pendingRemovals[registration] == nil
    }

    func scheduleNativeRemoval(
        _ registration: AXObserverRegistrationKey,
        cleanup: ObserverNativeRegistrationWork)
    {
        let id = UUID()
        let completion = NativeRemovalCompletion()
        self.pendingRemovals[registration] = PendingRemoval(
            id: id,
            completion: completion,
            cleanup: cleanup)
        let nativeWorkAdmission = self.nativeWorkAdmission
        Task.detached(priority: .utility) {
            await ObserverNativeWork.runPendingCleanup(
                admission: nativeWorkAdmission,
                operation: cleanup.remove)
            { error in
                completion.finish(with: error)
                Task { @MainActor in
                    self.completePendingRemoval(registration, id: id, error: error)
                }
            }
        }
    }

    func restartPendingRemovalIfNeeded(_ registration: AXObserverRegistrationKey) -> Bool {
        guard let pending = self.pendingRemovals[registration] else { return false }
        if let error = pending.completion.currentResult(),
           ObserverNativeWork.shouldKeepTrackingRemoval(error)
        {
            self.scheduleNativeRemoval(registration, cleanup: pending.cleanup)
        }
        return true
    }

    func finishPendingRemoval(_ registration: AXObserverRegistrationKey) async {
        guard self.pendingRemovals[registration] != nil else { return }
        _ = self.restartPendingRemovalIfNeeded(registration)
        guard let pending = self.pendingRemovals[registration] else { return }
        _ = await pending.completion.value()
        guard let error = pending.completion.currentResult() else { return }
        self.completePendingRemoval(registration, id: pending.id, error: error)
    }

    func finishPendingRemovalSynchronously(_ registration: AXObserverRegistrationKey) -> Bool? {
        if self.pendingRemovals[registration] == nil {
            return nil
        }
        _ = self.restartPendingRemovalIfNeeded(registration)
        guard let pending = self.pendingRemovals[registration] else { return false }
        let clock = ContinuousClock()
        guard let error = pending.completion.wait(until: clock.now.advanced(by: .milliseconds(750))) else {
            return false
        }
        self.completePendingRemoval(registration, id: pending.id, error: error)
        if self.pendingRemovals[registration] != nil {
            return false
        }
        return true
    }

    func completePendingRemoval(
        _ registration: AXObserverRegistrationKey,
        id: UUID,
        error: AXError)
    {
        guard let pending = self.pendingRemovals[registration], pending.id == id else { return }
        if ObserverNativeWork.shouldKeepTrackingRemoval(error) {
            return
        }
        self.pendingRemovals.removeValue(forKey: registration)
        self.finalizeNativeRemoval(registration, error: error)
    }
}
