import Logging
import Testing
@testable import AXorcist

@Suite("Logger isolation")
struct LoggerIsolationTests {
    @Test("convenience overloads are callable outside the main actor")
    func convenienceOverloadsAreNonisolated() {
        let logger = Logger(label: "AXorcistTests.LoggerIsolation")
        Self.logAllLevels(logger)
    }

    nonisolated private static func logAllLevels(_ logger: Logger) {
        logger.debug("debug")
        logger.info("info")
        logger.warning("warning")
        logger.error("error")
    }
}
