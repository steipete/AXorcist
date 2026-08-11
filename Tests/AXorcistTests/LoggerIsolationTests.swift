import Logging
import Testing
@testable import AXorcist

@Suite("Logger isolation")
struct LoggerIsolationTests {
    @Test
    func `convenience overloads are callable outside the main actor`() {
        let logger = Logger(label: "AXorcistTests.LoggerIsolation")
        Self.logAllLevels(logger)
    }

    private nonisolated static func logAllLevels(_ logger: Logger) {
        logger.debug("debug")
        logger.info("info")
        logger.warning("warning")
        logger.error("error")
    }
}
