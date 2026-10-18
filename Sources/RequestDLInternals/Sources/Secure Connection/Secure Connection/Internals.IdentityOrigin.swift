//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.URL
#endif

extension Internals {

    /// A host and a port: what an mTLS client identity is offered to.
    ///
    /// Both executors decide with this, so the same request is given the identity on both or on
    /// neither: `.nio` through `IdentityOrigins`, `.urlSession` through `TLSDelegate`. The same
    /// host on another port is another origin, since another port is another service, and a
    /// redirect to one is no reason to present the identity there.
    ///
    /// Host names compare without regard to case, and an IPv6 literal without its brackets, which
    /// is how AsyncHTTPClient hands it to a provider and how `URLProtectionSpace` names it.
    package struct IdentityOrigin: Hashable, Sendable {

        package let host: String
        package let port: Int

        package init(host: String, port: Int) {
            var host = host.lowercased()

            if host.hasPrefix("["), host.hasSuffix("]") {
                host = String(host.dropFirst().dropLast())
            }

            self.host = host
            self.port = port
        }

        /// The origin a request to `url` is made to, the port of its scheme when it names none.
        /// `nil` for a URL with no host.
        package init?(url: URL) {
            guard let host = url.host else {
                return nil
            }

            let scheme = url.scheme?.lowercased()
            self.init(host: host, port: url.port ?? (scheme == "http" ? 80 : 443))
        }
    }
}
