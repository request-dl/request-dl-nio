//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL

struct URLHostTests {

    @Test(arguments: ["example.com", "example.com:8443", "[::1]:8080", "127.0.0.1"])
    func isWellFormed_whenItHasNoDelimiter_isTrue(_ host: String) {
        #expect(URLHost.isWellFormed(host))
    }

    @Test(arguments: ["", "a/b", "a?b", "a#b", "a\\b", "a b", "a\tb", "a\nb", "a\u{7F}b"])
    func isWellFormed_whenItHasADelimiterOrIsEmpty_isFalse(_ host: String) {
        #expect(!URLHost.isWellFormed(host))
    }

    @Test(arguments: [
        "example.com",
        "xn--mnchen-3ya.de",
        "[::1]",
        "[2001:db8::1]",
        "[::ffff:192.168.0.1]",
        "[fe80::1%en0]",
        "[fe80::1%eth0.1]",
    ])
    func isWellFormedDecoded_whenItIsAHostOrAnIPv6Literal_isTrue(_ host: String) {
        #expect(URLHost.isWellFormed(decoded: host))
    }

    @Test(arguments: [
        "a@b.com",
        "a%b.com",
        "a:80",
        "a[b",
        "a]b",
        "[::1",
        "::1]",
        "[]",
        "[:g:]",
        "[::1]x]",
        "[fe80::1%]",
        "[fe80::1%a0]",
        "[fe80::1%en0/x]",
        "[fe80::1%23]",
    ])
    func isWellFormedDecoded_whenItCouldMoveAnythingAfterIt_isFalse(_ host: String) {
        #expect(!URLHost.isWellFormed(decoded: host))
    }
}
