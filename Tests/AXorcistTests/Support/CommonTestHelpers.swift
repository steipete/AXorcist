import Foundation

enum TestError: Error {
    case invalidInput
}

extension TimeInterval {
    static func milliseconds(_ value: Int) -> TimeInterval {
        TimeInterval(Double(value) / 1000.0)
    }
}
