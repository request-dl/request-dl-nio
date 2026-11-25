//
// See LICENSE for this package's licensing information.
//

#if canImport(NIOCore)

import Testing

@testable import RequestDLInternals

#if canImport(Darwin)
import Foundation
#endif

/// What `Internals.SOCKSAuthenticationRejectedError` recognises as a rejection by a SOCKS5
/// proxy, and what it leaves alone. A real rejection by a real proxy, on each executor, is in
/// `ProxySOCKSAuthenticationTests`.
struct InternalsSOCKSAuthenticationRejectedErrorTests {

    private struct Other: Error {}

    @Test
    func translating_whenTheErrorIsAnythingElse_returnsItUntouched() {
        #expect(Internals.SOCKSAuthenticationRejectedError.translating(Other()) is Other)
        #expect(Internals.SOCKSAuthenticationRejectedError.translating(CancellationError()) is CancellationError)
    }

    @Test
    func description_doesNotCarryTheCause() {
        let error = Internals.SOCKSAuthenticationRejectedError(underlying: Other())

        #expect(error.description == "The SOCKS proxy rejected the user name and the password it was given.")
    }

    #if canImport(Darwin)

    @Test
    func isURLSessionRejection_onlyForEAUTHInThePOSIXDomain() {
        let rejection = NSError(domain: NSPOSIXErrorDomain, code: Int(EAUTH))
        let otherCode = NSError(domain: NSPOSIXErrorDomain, code: Int(ECONNREFUSED))
        let otherDomain = NSError(domain: NSURLErrorDomain, code: Int(EAUTH))

        #expect(Internals.SOCKSAuthenticationRejectedError.isURLSessionRejection(rejection))
        #expect(!Internals.SOCKSAuthenticationRejectedError.isURLSessionRejection(otherCode))
        #expect(!Internals.SOCKSAuthenticationRejectedError.isURLSessionRejection(otherDomain))
    }

    #endif
}

#endif
