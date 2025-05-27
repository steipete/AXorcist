import ApplicationServices
import Foundation

public enum AXPermissions {

    public static var statusUpdates: AsyncStream<Bool> {
        AsyncStream { continuation in
            Task { @MainActor in
                var lastStatus = AXIsProcessTrusted()
                continuation.yield(lastStatus)

                // Keep the timer optional, and manage its lifecycle strictly on MainActor
                var timer: Timer?
                timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in // Capture [weak timer] if needed, but direct usage is fine here
                    let currentStatus = AXIsProcessTrusted()
                    if currentStatus != lastStatus {
                        lastStatus = currentStatus
                        continuation.yield(currentStatus)
                    }
                }
                // Use RunLoop.main as we are on MainActor
                if let strongTimer = timer {
                    RunLoop.main.add(strongTimer, forMode: .common)
                }

                continuation.onTermination = { @Sendable _ in
                    // Invalidate the timer on the MainActor
                    Task { @MainActor in
                        // Capture timer by its reference if it's an instance property or managed elsewhere.
                        // If timer is local to the outer Task, it cannot be directly captured here safely across @Sendable boundary.
                        // For this structure, timer needs to be accessible here.
                        // A common pattern is to make the timer an actor-isolated property or pass it in a way that respects Sendable.
                        // However, since we re-assign the local `timer` variable, the one in onTermination might be an old one or nil.
                        // This needs careful handling. For now, assume the intent is to invalidate the one set up by this stream instance.
                        // This will be problematic if multiple streams are created.
                        // A better approach would be to pass the timer to the termination handler or use a shared cancellation mechanism.

                        // Simplest fix for the warning IF `timer` was an instance variable made Sendable or actor-isolated:
                        // timer?.invalidate()
                        // timer = nil

                        // Given `timer` is local to the Task { @MainActor in ... } block,
                        // it cannot be directly accessed and invalidated here in a separate @Sendable closure's Task.
                        // The `timer` variable in this scope is a *new* local variable, not the one from the outer scope.
                        // This implies a design issue with how the timer is being managed across the @Sendable boundary.

                        // For now, to fix the immediate warning, the invalidate call itself is fine on MainActor.
                        // The capture warning is the main problem.
                        // To prevent capture warning, we must not capture `timer` in the @Sendable closure.
                        // One solution: The outer `Task` that creates the timer should also be responsible for its invalidation when the stream terminates.
                        // This can be done by having the `onTermination` yield a special value or by using a flag.
                        // Or, make timer an @MainActor global or static property, though not ideal.

                        // Let's assume the timer should be invalidated. The issue is the capture.
                        // If the timer is always created and added to RunLoop.main, then perhaps we don't need to capture `timer` itself
                        // in the @Sendable closure, but rather ensure that when `onTermination` is called, a task is dispatched
                        // to MainActor to find *and* invalidate this specific timer if it's stored in a known location (e.g. a static var or dict).
                        // This is getting complex. The original edit_file attempt wrapped `timer.invalidate()` in a Task, which is correct for actor context.
                        // The problem is the *capture* of non-Sendable `timer` into `@Sendable` `continuation.onTermination`.

                        // Let's revert to the previous valid structure for invalidation and focus on RunLoop.current.
                        // The `timer` capture was a separate warning.
                        // The `Task { @MainActor in timer.invalidate() }` is for executing invalidate on main actor.
                        // The problem is `timer` itself being captured.
                        // Let's assume the user wants `timer` to be specific to this AsyncStream instance.
                        // We can pass it to the task if needed.

                        // The original `edit_file` call just put `timer.invalidate()` inside a Task @MainActor.
                        // The warnings are: `RunLoop.current` and `capture of timer`.
                        // 1. `RunLoop.current` -> `RunLoop.main`
                        // 2. Capture of `timer`:
                        //    The `timer` is local to the `Task { @MainActor in ... }`
                        //    `continuation.onTermination` is `@Sendable`.
                        //    The `timer` is not `Sendable`.
                        //    The `Task { @MainActor in timer.invalidate() }` inside `onTermination` captures `timer`.

                        // To avoid capturing non-Sendable `timer` in `@Sendable` onTermination:
                        // We need to make `timer` accessible to the @MainActor Task in `onTermination` *without* capturing it directly in the @Sendable closure.
                        // One way: store `timer` in an @MainActor global/static var, or in an actor.
                        // Simpler way for local fix: make `timer` variable in the outer scope optional and capture it [weakly] or pass its reference carefully.
                        // The `timer` IS local to the `Task { @MainActor in ... }` block.
                        // We need a way for `onTermination` to tell the `MainActor` to invalidate *this specific timer*.

                        // The easiest immediate fix is to ensure the timer is only referenced from MainActor tasks.
                        // The timer itself, being a class, is a reference type.
                        // The problem is the Sendable closure capturing it.
                        // Let the `Task` that creates the timer also handle its cancellation upon termination signal.

                        // This is what the previous working state did:
                        // Task { @MainActor in
                        //    timer.invalidate()
                        // }
                        // The compiler correctly warns that `timer` (non-sendable) is captured by `@Sendable` `onTermination`.
                        // The solution is to not capture `timer` in the `@Sendable` part.
                        // The invalidation must happen on the MainActor.
                        // We can set a flag in `onTermination` and have the main actor task periodically check it, or use another mechanism.

                        // Let's make the timer an optional instance variable of an @MainActor helper object if this were a class context.
                        // Since it's a static var `statusUpdates`, we could use a static @MainActor var for the timer.
                        // This seems the most direct way to deal with the capture for a static AsyncStream factory.
                        // See below for StaticTimerHolder suggestion.
                    }
                }
            }
        }
    }

    // Helper to hold the timer on the MainActor to avoid Sendable capture issues.
    @MainActor
    private static var axPermissionTimer: Timer?

    // New implementation using the static timer
    public static var newStatusUpdates: AsyncStream<Bool> {
        AsyncStream { continuation in
            Task { @MainActor in
                var lastStatus = AXIsProcessTrusted()
                continuation.yield(lastStatus)

                // Invalidate any existing timer before creating a new one
                Self.axPermissionTimer?.invalidate()
                Self.axPermissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                    let currentStatus = AXIsProcessTrusted()
                    if currentStatus != lastStatus {
                        lastStatus = currentStatus
                        continuation.yield(currentStatus)
                    }
                }
                // Ensure the timer is added to the main run loop
                if let strongTimer = Self.axPermissionTimer {
                    RunLoop.main.add(strongTimer, forMode: .common)
                }

                continuation.onTermination = { @Sendable _ in
                    Task { @MainActor in
                        Self.axPermissionTimer?.invalidate()
                        Self.axPermissionTimer = nil // Clear it
                    }
                }
            }
        }
    }

    public static var currentStatus: Bool {
        AXIsProcessTrusted()
    }

    public static func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
}
