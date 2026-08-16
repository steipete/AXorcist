import Foundation
import Testing
@testable import AXorcist

@Suite("Permission change stream")
nonisolated struct PermissionChangeStreamTests {
    @Test
    func `permissionChanges cancel does not join the main queue`() async {
        let stream = await MainActor.run {
            AXPermissionHelpers.permissionChanges(interval: 60)
        }
        let completed = await Self.runOnDedicatedThread {
            Self.cancelCompletesWhileMainQueueIsBusy(stream: stream)
        }

        #expect(completed)
    }

    @Test
    func `permissionChanges skip start after an already-terminated stream`() async {
        let scheduled = PermissionTimerScheduleBox()
        let skipped = await Self.runOnDedicatedThread {
            Self.cancelBeforeQueuedStartRuns(scheduled: scheduled)
        }

        #expect(skipped)
        #expect(!scheduled.wasMarked)
    }

    private nonisolated static func cancelCompletesWhileMainQueueIsBusy(
        stream: AsyncStream<Bool>) -> Bool
    {
        let consumeFinished = DispatchSemaphore(value: 0)
        let consume = Task.detached {
            for await _ in stream {}
            consumeFinished.signal()
        }

        let mainHeld = DispatchSemaphore(value: 0)
        let releaseMain = DispatchSemaphore(value: 0)
        DispatchQueue.main.async {
            mainHeld.signal()
            releaseMain.wait()
        }
        mainHeld.wait()

        Thread.detachNewThread {
            consume.cancel()
        }
        let finished = consumeFinished.wait(timeout: .now() + .milliseconds(400)) == .success
        releaseMain.signal()
        return finished
    }

    private nonisolated static func cancelBeforeQueuedStartRuns(
        scheduled: PermissionTimerScheduleBox) -> Bool
    {
        let mainHeld = DispatchSemaphore(value: 0)
        let streamCreated = DispatchSemaphore(value: 0)
        let releaseMain = DispatchSemaphore(value: 0)

        DispatchQueue.main.async {
            mainHeld.signal()
            streamCreated.wait()
            releaseMain.wait()
        }
        mainHeld.wait()

        _ = AXPermissionHelpers.permissionChanges(interval: 60) {
            scheduled.mark()
        }
        streamCreated.signal()
        releaseMain.signal()
        let flushed = DispatchSemaphore(value: 0)
        DispatchQueue.main.async {
            flushed.signal()
        }
        flushed.wait()
        return !scheduled.wasMarked
    }

    private nonisolated static func runOnDedicatedThread<Value: Sendable>(
        _ operation: @escaping @Sendable () -> Value) async -> Value
    {
        await withCheckedContinuation { continuation in
            Thread.detachNewThread {
                continuation.resume(returning: operation())
            }
        }
    }
}

private final nonisolated class PermissionTimerScheduleBox: @unchecked Sendable {
    private let lock = NSLock()
    private var marked = false

    func mark() {
        self.lock.lock()
        self.marked = true
        self.lock.unlock()
    }

    var wasMarked: Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.marked
    }
}
