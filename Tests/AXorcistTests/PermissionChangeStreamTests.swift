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
        let completed = await Task.detached {
            Self.cancelCompletesWhileMainQueueIsBusy(stream: stream)
        }.value

        #expect(completed)
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
}
