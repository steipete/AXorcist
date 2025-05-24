import ApplicationServices
import Foundation

public enum AXTrustUtil {
    // Define a Swift constant for the C global string, initialized safely.
    // Ensure this is initialized only once and the value is deeply copied.
    private static let swiftAXTrustedCheckOptionPrompt: String = (kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String)

    /// Checks if the current process is trusted for accessibility access.
    ///
    /// - Parameter promptIfNeeded: If `true`, the system will prompt the user to grant accessibility access if not already trusted.
    /// - Returns: `true` if the process is trusted, `false` otherwise.
    public static func isAPIEnabled(promptIfNeeded: Bool = false) -> Bool {
        let options: [String: Bool]? = promptIfNeeded ? [Self.swiftAXTrustedCheckOptionPrompt: true] : nil
        return AXIsProcessTrustedWithOptions(options as CFDictionary?)
    }
}
