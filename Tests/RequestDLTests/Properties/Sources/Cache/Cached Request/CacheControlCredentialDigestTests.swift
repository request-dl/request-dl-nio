//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals
import Testing

@testable import RequestDL

/// What the cache records in place of a credential.
struct CacheControlCredentialDigestTests {

    @Test
    func digest_isStableAndNeverTheValue() {
        let first = Internals.CacheControl.digest(ofCredential: "Bearer secret-token", field: "authorization")
        let again = Internals.CacheControl.digest(ofCredential: "Bearer secret-token", field: "authorization")

        #expect(first == again)
        #expect(!first.contains("secret-token"))
        #expect(first.hasPrefix("sha256:"))

        // 7 for the prefix and 64 hexadecimal digits for 32 bytes.
        #expect(first.count == 7 + 64)
    }

    @Test
    func digest_differsByCredential() {
        #expect(
            Internals.CacheControl.digest(ofCredential: "Bearer a", field: "authorization")
                != Internals.CacheControl.digest(ofCredential: "Bearer b", field: "authorization")
        )
    }

    /// The same bytes under another header are not the same credential.
    @Test
    func digest_differsByField() {
        #expect(
            Internals.CacheControl.digest(ofCredential: "session=a", field: "cookie")
                != Internals.CacheControl.digest(ofCredential: "session=a", field: "authorization")
        )
    }

    /// A digest that starts with a zero byte keeps its two digits.
    @Test
    func digest_alwaysHasSixtyFourHexadecimalDigits() {
        for index in 0..<200 {
            let digest = Internals.CacheControl.digest(ofCredential: "value-\(index)", field: "cookie")

            #expect(digest.count == 71, "\(digest)")
        }
    }
}
