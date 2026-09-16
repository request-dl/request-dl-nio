//
// See LICENSE for this package's licensing information.
//

// `Reachable under `.nio` only` (see below) means this protocol's own signature is unusable
// without NIOCore too: `callAsFunction(_:)` takes a `ByteBuffer`, so gating it here, rather than
// letting a NIOCore-less build fail deep inside this file with a "cannot find type" error, gives
// a conformer a clean "this protocol doesn't exist" instead.
#if canImport(NIOCore)

import NIOCore

/// A protocol for implementing `SSLKEYLOGFILE` support.
///
/// ``SSLKeyLogger`` defines a method that can be used to log keys in the format expected by
/// tools that support the `SSLKEYLOGFILE`.
///
/// - Important: Reachable under `.nio` only. This is a **permanent** limitation, not a gap
/// awaiting a fix. Neither Network.framework nor `URLSession` exposes any public API for
/// observing per-session TLS secrets.
///
/// A session with a key logger configured that also resolves to `.nioTransportServices` crashes
/// the process outright (`TLSConfiguration.keyLogCallback` `preconditionFailure`s in
/// AsyncHTTPClient's own NIOTransportServices bridge), which is exactly why
/// `resolveExecutor()`/`requireExecutor(_:)` steer away from both non-`.nio` executors whenever
/// this is set, rather than letting that reach the OS layer at all.
public protocol SSLKeyLogger: Sendable, AnyObject {

    ///
    /// Function for logging keys in the format expected by tools that support the
    /// `SSLKEYLOGFILE`.
    ///
    /// - Parameter bytes: The bytes to be logged.
    ///
    func callAsFunction(_ bytes: ByteBuffer)
}

#endif
