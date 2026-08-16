import ApplicationServices
import Foundation

@MainActor
extension AXObserverCenter {
    func subscribeNativeSetupError(
        _ registration: AXObserverRegistrationKey,
        expectedGeneration: UInt64,
        joined: AXError?,
        hasNativeRegistration: Bool) -> AXError
    {
        if let joined {
            return joined
        }
        if hasNativeRegistration {
            return .success
        }
        guard ObserverNativeWork.canLaunchNativeAdd(
            hasPendingAdd: self.pendingRegistrations[registration] != nil,
            hasUnconfirmedRemoval: self.pendingRemovals[registration] != nil)
        else {
            return .cannotComplete
        }
        return self.setupUnderlyingObserver(registration, expectedGeneration: expectedGeneration)
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
                    error: stored,
                    state: self.nativeRegistrationStates[registration])
            }
            return NativeRegistrationSetupResult(error: .cannotComplete, state: nil)
        }
        let id = UUID()
        let completion = NativeRemovalCompletion()
        let task = Task { @MainActor in
            let error = await self.setupUnderlyingObserverAsync(
                registration,
                operationID: id,
                expectedGeneration: expectedGeneration)
            if let stored = completion.currentResult() {
                return NativeRegistrationSetupResult(
                    error: stored,
                    state: self.nativeRegistrationStates[registration])
            }
            return NativeRegistrationSetupResult(error: error, state: nil)
        }
        self.pendingRegistrations[registration] = PendingRegistration(
            id: id,
            expectedGeneration: expectedGeneration,
            task: task,
            completion: completion)
        return await task.value
    }

    func finishPendingRegistrationSynchronously(
        _ registration: AXObserverRegistrationKey,
        expectedGeneration: UInt64,
        expectedEpoch: ObserverStateEpoch) -> AXError?
    {
        guard let pending = self.pendingRegistrations[registration] else { return nil }
        guard pending.expectedGeneration == expectedGeneration else { return .cannotComplete }
        pending.completion.parkWaiter()
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while pending.completion.currentResult() == nil, clock.now < deadline {
            _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }
        pending.completion.unparkWaiter()
        guard let error = pending.completion.currentResult() else { return .cannotComplete }
        let expectedState = NativeRegistrationState(
            operationID: pending.id,
            processGeneration: expectedGeneration)
        let alreadyCommitted = self.nativeRegistrationStates[registration] == expectedState
        guard self.currentStateEpoch(for: registration.subscription.pid) == expectedEpoch else {
            return .cannotComplete
        }
        if error == .success {
            guard self.observerGenerations[registration.subscription.pid]?.startIdentity == expectedGeneration else {
                return .cannotComplete
            }
            guard alreadyCommitted else { return nil }
        }
        if error != .success {
            self.removeObserverIfUnused(targetPid: registration.subscription.pid)
        }
        return error
    }

    func setupUnderlyingObserverAsync(
        _ registration: AXObserverRegistrationKey,
        operationID: UUID,
        expectedGeneration: UInt64) async -> AXError
    {
        let targetPid = registration.subscription.pid
        guard let observer = await self.getOrCreateObserverAsync(
            for: targetPid,
            expectedGeneration: expectedGeneration)
        else {
            self.finishOwnedPendingAdd(
                registration,
                operationID: operationID,
                error: .failure)
            return .failure
        }
        let registrationWork = self.nativeNotificationRegistration(for: registration, observer: observer)
        let nativeWorkAdmission = self.nativeWorkAdmission
        let first = await ObserverNativeWork.runPendingAdd(
            admission: nativeWorkAdmission,
            operation: registrationWork.add)
        { nativeError in
            Task { @MainActor in
                await self.completePendingAdd(
                    registration,
                    operationID: operationID,
                    expectedGeneration: expectedGeneration,
                    cleanup: registrationWork,
                    outcome: ObserverNativeWork.PendingNativeFirstResult(
                        error: nativeError,
                        timedOut: true))
            }
        }
        if !first.timedOut {
            await self.completePendingAdd(
                registration,
                operationID: operationID,
                expectedGeneration: expectedGeneration,
                cleanup: registrationWork,
                outcome: first)
        }
        return first.error
    }

    func completePendingAdd(
        _ registration: AXObserverRegistrationKey,
        operationID: UUID,
        expectedGeneration: UInt64,
        cleanup: NativeNotificationRegistration,
        outcome: ObserverNativeWork.PendingNativeFirstResult) async
    {
        let finalGeneration = await ObserverNativeWork.boundedProcessUniqueIdentity(
            registration.subscription.pid,
            admission: self.nativeWorkAdmission)
        let pending = self.pendingRegistrations[registration]
        let stillPending = pending?.id == operationID
        let waiterCount = stillPending ? (pending?.completion.waiterCount ?? 0) : 0
        let generationMatches = finalGeneration == expectedGeneration
        let disposition = ObserverNativeWork.pendingAddDisposition(
            nativeError: outcome.error,
            stillPending: stillPending,
            waiterCount: waiterCount,
            generationMatches: generationMatches,
            isLate: outcome.timedOut)

        self.logObserverAddResult(
            targetPid: registration.subscription.pid,
            notification: registration.subscription.notification,
            error: outcome.error)

        switch disposition {
        case .commit:
            self.nativeRegistrationStates[registration] = NativeRegistrationState(
                operationID: operationID,
                processGeneration: expectedGeneration)
            if stillPending {
                pending?.completion.finish(with: .success)
                self.pendingRegistrations.removeValue(forKey: registration)
            }
        case .pendingRemoval:
            if stillPending {
                pending?.completion.finish(with: .cannotComplete)
                self.pendingRegistrations.removeValue(forKey: registration)
            }
            if !generationMatches {
                self.resetObserverGeneration(
                    for: registration.subscription.pid,
                    ifMatching: expectedGeneration)
            }
            if stillPending || self.shouldScheduleUnownedLateRemoval(registration) {
                self.scheduleNativeRemoval(registration, cleanup: cleanup)
            }
        case .finishOnly:
            if stillPending {
                pending?.completion.finish(with: outcome.error)
                self.pendingRegistrations.removeValue(forKey: registration)
            }
            self.removeObserverIfUnused(targetPid: registration.subscription.pid)
        }
    }

    func finishOwnedPendingAdd(
        _ registration: AXObserverRegistrationKey,
        operationID: UUID,
        error: AXError)
    {
        guard self.pendingRegistrations[registration]?.id == operationID else { return }
        let pending = self.pendingRegistrations.removeValue(forKey: registration)
        pending?.completion.finish(with: error)
        self.removeObserverIfUnused(targetPid: registration.subscription.pid)
    }

    func shouldScheduleUnownedLateRemoval(_ registration: AXObserverRegistrationKey) -> Bool {
        self.pendingRegistrations[registration] == nil
            && self.nativeRegistrationStates[registration] == nil
            && self.pendingRemovals[registration] == nil
    }

    func scheduleNativeRemoval(
        _ registration: AXObserverRegistrationKey,
        cleanup: NativeNotificationRegistration)
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
