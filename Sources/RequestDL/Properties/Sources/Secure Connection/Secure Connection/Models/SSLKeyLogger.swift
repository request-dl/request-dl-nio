//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

/// A protocol for implementing `SSLKEYLOGFILE` support.
///
/// ``SSLKeyLogger`` defines a method that can be used to log keys in the format expected by
/// tools that support the `SSLKEYLOGFILE`.
public typealias SSLKeyLogger = RequestDLInternals.SSLKeyLogger
