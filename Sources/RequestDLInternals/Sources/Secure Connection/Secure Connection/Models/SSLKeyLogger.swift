//
// See LICENSE for this package's licensing information.
//

import NIOCore

/// A protocol for implementing `SSLKEYLOGFILE` support.
///
/// ``SSLKeyLogger`` defines a method that can be used to log keys in the format expected by
/// tools that support the `SSLKEYLOGFILE`.
///
/// - Important: Reachable under `.nio` only -- this is a **permanent** limitation, not a gap
/// awaiting a fix. Neither Network.framework nor `URLSession` exposes any public API for
/// observing per-session TLS secrets; a session with a key logger configured that also resolves
/// to `.nioTransportServices` crashes the process outright
/// (`TLSConfiguration.keyLogCallback` `preconditionFailure`s in AsyncHTTPClient's own
/// NIOTransportServices bridge), which is exactly why `resolveExecutor()`/`requireExecutor(_:)`
/// steer away from both non-`.nio` executors whenever this is set, rather than letting that
/// reach the OS layer at all.
public protocol SSLKeyLogger: Sendable, AnyObject {

    ///
    /// Function for logging keys in the format expected by tools that support the
    /// `SSLKEYLOGFILE`.
    ///
    /// - Parameter bytes: The bytes to be logged.
    ///
    func callAsFunction(_ bytes: ByteBuffer)
}
