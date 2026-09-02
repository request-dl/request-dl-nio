//
// See LICENSE for this package's licensing information.
//

/// How many of the suites carrying `.concurrent(_:)` may run at once, or `nil` to let
/// `ConcurrentExecutionTrait` skip the semaphore entirely.
///
/// The `AsyncLock.Watchdog` false-positive investigation this throttling exists for was
/// observed only on Apple *simulator* runners — iOS, iPadOS (which shares `os(iOS)` with iPhone;
/// there is no separate compile-time identifier for it), watchOS, visionOS — never on macOS,
/// Mac Catalyst, tvOS, Linux, or Android, which don't run the tests inside a simulator's
/// host-bridged, scheduler-contended environment in the first place. Actually gating the limit
/// still matters there, not just documenting it: an unnecessary semaphore serializes otherwise
/// independent suites for no reason on every platform that was never flaky.
package let watchdogAffectedPlatformConcurrencyLimit: Int? = {
    #if (os(iOS) && !targetEnvironment(macCatalyst)) || os(watchOS) || os(visionOS)
    return 2
    #else
    return nil
    #endif
}()
