import Foundation

@discardableResult
func startStreaming(pipe: Pipe) -> () -> Data {
    let queue = DispatchQueue(label: "axorcist.tests.pipe-stream.\(UUID().uuidString)", qos: .userInitiated)
    var collected = Data()
    let group = DispatchGroup()

    group.enter()
    pipe.fileHandleForReading.readabilityHandler = { handle in
        let chunk = handle.availableData
        if chunk.isEmpty {
            handle.readabilityHandler = nil
            group.leave()
            return
        }
        queue.async {
            collected.append(chunk)
        }
    }

    return {
        group.wait()
        return queue.sync { collected }
    }
}
