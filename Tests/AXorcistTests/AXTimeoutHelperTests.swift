import Foundation
@testable import AXorcist
import Testing

@Suite("AXTimeoutHelper")
struct AXTimeoutHelperTests {
    @MainActor
    @Test("completes before timeout")
    func completesBeforeTimeout() async throws {
        let value: Int = try await AXTimeoutHelper.withTimeout(seconds: 0.2) {
            try await Task.sleep(nanoseconds: 50_000_000)
            return 7
        }
        #expect(value == 7)
    }

    @MainActor
    @Test("throws on timeout")
    func throwsOnTimeout() async {
        do {
            _ = try await AXTimeoutHelper.withTimeout(seconds: 0.05) {
                try await Task.sleep(nanoseconds: 200_000_000)
                return 1
            }
            Issue.record("Expected timeout but succeeded")
        } catch let error as AXTimeoutError {
            #expect(String(describing: error).contains("timed out"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
