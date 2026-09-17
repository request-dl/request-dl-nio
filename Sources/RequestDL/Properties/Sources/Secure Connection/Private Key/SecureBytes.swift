//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

/// A byte sequence for a password/passphrase, such as ``PrivateKey``'s password parameter,
/// that doesn't require NIO to construct or use the way `NIOSSLSecureBytes` does.
///
/// See `RequestDLInternals.SecureBytes`'s own doc comment for what backs this on each platform.
public typealias SecureBytes = RequestDLInternals.SecureBytes
