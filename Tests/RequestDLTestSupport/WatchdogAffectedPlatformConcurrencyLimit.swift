//
// See LICENSE for this package's licensing information.
//

/// How many of the suites carrying `.concurrent(_:)` may run at once, or `nil` to let
/// `ConcurrentExecutionTrait` skip the semaphore entirely.
///
/// The `AsyncLock.Watchdog` false positives this throttling exists for were observed only on
/// Apple *simulator* runners: iOS, iPadOS (which shares `os(iOS)` with iPhone; there is no
/// separate compile-time identifier for it), watchOS, visionOS and, as the same starvation
/// showed up there later (suites reporting hundreds of seconds, waits expiring, timing-based
/// assertions off by one), tvOS. Never on macOS, Mac Catalyst, Linux, or Android, which don't
/// run the tests inside a simulator's host-bridged, scheduler-contended environment.
/// Actually gating the limit still matters there, not just documenting it: an unnecessary
/// semaphore serializes otherwise independent suites for no reason on every platform that
/// was never flaky.
package let watchdogAffectedPlatformConcurrencyLimit: Int? = {
    #if (os(iOS) && !targetEnvironment(macCatalyst)) || os(tvOS) || os(watchOS) || os(visionOS)
    return 2
    #else
    return nil
    #endif
}()
