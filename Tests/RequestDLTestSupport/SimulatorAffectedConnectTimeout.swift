//
// See LICENSE for this package's licensing information.
//

/// Seconds a test lets a connection take to establish, longer on the Apple simulator runners.
///
/// A CI simulator job runs the whole suite on a host-bridged, scheduler-contended runner, where a
/// TLS handshake that takes milliseconds anywhere else can outlast a default connect timeout. See
/// `simulatorAffectedURLSessionRequestTimeout` for the same reasoning applied to `URLSession`'s
/// own request timeout.
///
/// A separate constant, not that one: it is Darwin only, and the NIO tests that need this one also
/// compile on every other platform.
package let simulatorAffectedConnectTimeoutSeconds: Int64 = {
    #if (os(iOS) && !targetEnvironment(macCatalyst)) || os(tvOS) || os(watchOS) || os(visionOS)
    return 90
    #else
    return 30
    #endif
}()
