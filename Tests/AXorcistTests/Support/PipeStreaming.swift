import Foundation

private final class PipeStreamBuffer: @unchecked Sendable {
    private let queue = DispatchQueue(
        label: "axorcist.tests.pipe-stream.\(UUID().uuidString)",
        qos: .userInitiated)
    nonisolated(unsafe) private var data = Data()

    nonisolated func append(_ chunk: Data) {
        self.queue.async {
            self.data.append(chunk)
        }
    }

    nonisolated func snapshot() -> Data {
        self.queue.sync { self.data }
    }
}

@discardableResult
func startStreaming(pipe: Pipe) -> () -> Data {
    let buffer = PipeStreamBuffer()
    let group = DispatchGroup()

    group.enter()
    pipe.fileHandleForReading.readabilityHandler = { handle in
        let chunk = handle.availableData
        if chunk.isEmpty {
            handle.readabilityHandler = nil
            group.leave()
            return
        }
        buffer.append(chunk)
    }

    return {
        group.wait()
        return buffer.snapshot()
    }
}
