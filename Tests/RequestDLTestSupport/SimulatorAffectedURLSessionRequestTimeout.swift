//
// See LICENSE for this package's licensing information.
//

#if canImport(Darwin)
import Foundation

/// `timeoutIntervalForRequest` deliberately kept short (not the 60s default) on tests that drive
/// `Internals.URLSessionClient` directly against a real `LocalServer` -- cheap insurance against a
/// future regression hanging the suite instead of failing fast, sized against CI Simulator
/// scheduler jitter rather than against how long the request itself should actually take.
///
/// Bumped once already (5s -> 15s -> 30s, see request-dl-nio#319) after CI flaked on it -- 30s
/// still wasn't enough: a genuine `NSURLErrorTimedOut` was directly observed on tvOS at 30s under
/// contention (request-dl-nio#327), a platform this margin previously wasn't even suspected of
/// affecting. 90s gives real headroom on every Apple *Simulator* platform (iOS, iPadOS -- shares
/// `os(iOS)` with iPhone --, tvOS, watchOS, visionOS), which unlike macOS/Mac Catalyst (host
/// speed) or Linux/Android (don't run this suite under a simulator at all) have now each been
/// directly observed stalling under CI contention. Non-Simulator platforms keep the original 30s:
/// a real regression there still fails well short of the 60s default.
package let simulatorAffectedURLSessionRequestTimeout: TimeInterval = {
    #if (os(iOS) && !targetEnvironment(macCatalyst)) || os(tvOS) || os(watchOS) || os(visionOS)
    return 90
    #else
    return 30
    #endif
}()
#endif
