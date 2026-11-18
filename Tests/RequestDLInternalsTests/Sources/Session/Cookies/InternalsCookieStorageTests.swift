//
// See LICENSE for this package's licensing information.
//

import Foundation
import Testing

@testable import RequestDLInternals

struct InternalsCookieStorageTests {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func url(_ string: String) -> URL {
        URL(string: string)!
    }

    private func header(
        _ storage: Internals.CookieStorage,
        _ target: String,
        at date: Date? = nil
    ) -> String? {
        storage.cookieHeader(for: url(target), now: date ?? now)
    }

    // MARK: - Basics

    @Test
    func cookieHeader_whenCookieWasStored_sendsItToTheSameHostOnly() {
        let storage = Internals.CookieStorage()
        storage.store(setCookieValues: ["sid=abc"], for: url("https://example.com/login"), now: now)

        #expect(header(storage, "https://example.com/home") == "sid=abc")
        #expect(header(storage, "https://sub.example.com/home") == nil)
        #expect(header(storage, "https://other.com/home") == nil)
    }

    @Test
    func cookieHeader_whenDomainAttributeIsPresent_sendsItToSubdomains() {
        let storage = Internals.CookieStorage()
        storage.store(setCookieValues: ["sid=abc; Domain=.example.com"], for: url("https://www.example.com/"), now: now)

        #expect(header(storage, "https://example.com/") == "sid=abc")
        #expect(header(storage, "https://api.example.com/") == "sid=abc")
        #expect(header(storage, "https://notexample.com/") == nil)
    }

    @Test
    func store_whenDomainDoesNotCoverTheHost_rejectsTheCookie() {
        let storage = Internals.CookieStorage()
        storage.store(setCookieValues: ["sid=abc; Domain=other.com"], for: url("https://example.com/"), now: now)

        #expect(storage.snapshot(now: now).isEmpty)
    }

    @Test
    func store_whenHostIsAnIPAddress_ignoresADomainThatIsNotTheHostItself() {
        let storage = Internals.CookieStorage()
        storage.store(setCookieValues: ["a=1; Domain=0.0.1"], for: url("http://127.0.0.1/"), now: now)
        storage.store(setCookieValues: ["b=2; Domain=127.0.0.1"], for: url("http://127.0.0.1/"), now: now)

        let cookies = storage.snapshot(now: now)
        #expect(cookies.map(\.name) == ["b"])
        #expect(cookies.first?.hostOnly == true)
    }

    // MARK: - Path

    @Test
    func cookieHeader_whenPathAttributeIsMissing_usesTheDefaultPath() {
        let storage = Internals.CookieStorage()
        storage.store(setCookieValues: ["a=1"], for: url("https://example.com/api/v1/users"), now: now)

        #expect(storage.snapshot(now: now).first?.path == "/api/v1")
        #expect(header(storage, "https://example.com/api/v1/other") == "a=1")
        #expect(header(storage, "https://example.com/api/v2") == nil)
        #expect(header(storage, "https://example.com/api/v1x") == nil)
    }

    @Test
    func defaultPath_followsRFC6265() {
        #expect(Internals.Cookie.defaultPath(of: "") == "/")
        #expect(Internals.Cookie.defaultPath(of: "/") == "/")
        #expect(Internals.Cookie.defaultPath(of: "/a") == "/")
        #expect(Internals.Cookie.defaultPath(of: "/a/b") == "/a")
        #expect(Internals.Cookie.defaultPath(of: "/a/b/") == "/a/b")
    }

    @Test
    func cookieHeader_whenSeveralCookiesMatch_putsLongerPathsFirstThenOlderOnes() {
        let storage = Internals.CookieStorage()
        storage.store(setCookieValues: ["root=1; Path=/"], for: url("https://example.com/"), now: now)
        storage.store(setCookieValues: ["deep=2; Path=/a/b"], for: url("https://example.com/"), now: now.addingTimeInterval(1))
        storage.store(setCookieValues: ["mid=3; Path=/a"], for: url("https://example.com/"), now: now.addingTimeInterval(2))
        storage.store(setCookieValues: ["root2=4; Path=/"], for: url("https://example.com/"), now: now.addingTimeInterval(3))

        #expect(header(storage, "https://example.com/a/b/c") == "deep=2; mid=3; root=1; root2=4")
    }

    // MARK: - Secure

    @Test
    func cookieHeader_whenCookieIsSecure_isSentOverTLSAndLoopbackOnly() {
        let storage = Internals.CookieStorage()
        storage.store(setCookieValues: ["s=1; Secure"], for: url("https://example.com/"), now: now)
        storage.store(setCookieValues: ["l=1; Secure"], for: url("http://localhost:8080/"), now: now)

        #expect(header(storage, "https://example.com/") == "s=1")
        #expect(header(storage, "http://example.com/") == nil)
        #expect(header(storage, "http://localhost:9090/") == "l=1")
    }

    @Test
    func store_whenSecureCookieComesFromAnInsecureOrigin_rejectsIt() {
        let storage = Internals.CookieStorage()
        storage.store(setCookieValues: ["s=1; Secure"], for: url("http://example.com/"), now: now)

        #expect(storage.snapshot(now: now).isEmpty)
    }

    @Test
    func store_whenInsecureOriginReplacesASecureCookie_keepsTheSecureOne() {
        let storage = Internals.CookieStorage()
        storage.store(setCookieValues: ["s=good; Secure"], for: url("https://example.com/"), now: now)
        storage.store(setCookieValues: ["s=evil"], for: url("http://example.com/"), now: now)
        storage.store(setCookieValues: ["s=; Max-Age=0"], for: url("http://example.com/"), now: now)

        #expect(header(storage, "https://example.com/") == "s=good")
    }

    @Test
    func store_whenPrefixRulesAreBroken_rejectsTheCookie() {
        let storage = Internals.CookieStorage()
        let target = url("https://example.com/")

        storage.store(setCookieValues: ["__Secure-a=1"], for: target, now: now)
        storage.store(setCookieValues: ["__Host-b=1; Secure; Domain=example.com; Path=/"], for: target, now: now)
        storage.store(setCookieValues: ["__Host-c=1; Secure; Path=/x"], for: target, now: now)
        storage.store(setCookieValues: ["__Secure-ok=1; Secure"], for: target, now: now)
        storage.store(setCookieValues: ["__Host-ok=1; Secure; Path=/"], for: target, now: now)

        #expect(Set(storage.snapshot(now: now).map(\.name)) == ["__Secure-ok", "__Host-ok"])
    }

    // MARK: - Expiry and replacement

    @Test
    func cookieHeader_whenMaxAgeElapsed_dropsTheCookie() {
        let storage = Internals.CookieStorage()
        storage.store(setCookieValues: ["a=1; Max-Age=60"], for: url("https://example.com/"), now: now)

        #expect(header(storage, "https://example.com/", at: now.addingTimeInterval(59)) == "a=1")
        #expect(header(storage, "https://example.com/", at: now.addingTimeInterval(61)) == nil)
    }

    @Test
    func store_whenMaxAgeAndExpiresDisagree_maxAgeWins() {
        let storage = Internals.CookieStorage()
        storage.store(
            setCookieValues: ["a=1; Expires=Thu, 01 Jan 1970 00:00:01 GMT; Max-Age=3600"],
            for: url("https://example.com/"),
            now: now
        )

        #expect(header(storage, "https://example.com/") == "a=1")
    }

    @Test
    func store_whenMaxAgeHasASign_ignoresThatAttribute() {
        let storage = Internals.CookieStorage()
        storage.store(setCookieValues: ["a=1; Max-Age=+5"], for: url("https://example.com/"), now: now)

        #expect(storage.snapshot(now: now).first?.expires == nil)
    }

    @Test
    func store_whenExpiredCookieHasAMatch_deletesIt() {
        let storage = Internals.CookieStorage()
        storage.store(setCookieValues: ["a=1"], for: url("https://example.com/"), now: now)
        storage.store(setCookieValues: ["a=; Max-Age=0"], for: url("https://example.com/"), now: now)
        storage.store(setCookieValues: ["b=1"], for: url("https://example.com/"), now: now)
        storage.store(setCookieValues: ["b=; Expires=Thu, 01 Jan 1970 00:00:00 GMT"], for: url("https://example.com/"), now: now)

        #expect(storage.snapshot(now: now).isEmpty)
    }

    @Test
    func store_whenSameNameDomainAndPath_replacesAndKeepsTheCreationTime() {
        let storage = Internals.CookieStorage()
        storage.store(setCookieValues: ["a=1"], for: url("https://example.com/"), now: now)
        storage.store(setCookieValues: ["a=2"], for: url("https://example.com/"), now: now.addingTimeInterval(10))

        let cookies = storage.snapshot(now: now)
        #expect(cookies.count == 1)
        #expect(cookies.first?.value == "2")
        #expect(cookies.first?.creation == now)
    }

    @Test
    func store_whenHostOnlyAndDomainCookiesShareANameAndPath_keepsBoth() {
        let storage = Internals.CookieStorage()
        storage.store(setCookieValues: ["a=host"], for: url("https://example.com/"), now: now)
        storage.store(setCookieValues: ["a=domain; Domain=example.com"], for: url("https://example.com/"), now: now)

        #expect(storage.snapshot(now: now).count == 2)
    }

    // MARK: - Hostile input

    @Test
    func store_whenNameOrValueHasControlCharactersOrIsHuge_rejectsTheCookie() {
        let storage = Internals.CookieStorage()
        let target = url("https://example.com/")

        storage.store(setCookieValues: ["a=1\u{01}2"], for: target, now: now)
        storage.store(setCookieValues: ["a\u{7F}=1"], for: target, now: now)
        storage.store(setCookieValues: ["big=" + String(repeating: "x", count: 4_100)], for: target, now: now)
        storage.store(setCookieValues: ["=novalue-name"], for: target, now: now)
        storage.store(setCookieValues: ["no-equals-sign"], for: target, now: now)

        #expect(storage.snapshot(now: now).isEmpty)
    }

    @Test
    func store_whenValueIsQuoted_keepsTheQuotesVerbatim() {
        let storage = Internals.CookieStorage()
        storage.store(setCookieValues: ["a=\"x y\""], for: url("https://example.com/"), now: now)

        #expect(header(storage, "https://example.com/") == "a=\"x y\"")
    }

    @Test
    func store_whenLimitsAreExceeded_evictsTheLeastRecentlyUsed() {
        let storage = Internals.CookieStorage()
        let target = url("https://example.com/")
        let total = Internals.CookieStorage.maximumCookiesPerDomain + 5

        for index in 0..<total {
            storage.store(setCookieValues: ["c\(index)=1"], for: target, now: now.addingTimeInterval(TimeInterval(index)))
        }

        let names = Set(storage.snapshot(now: now).map(\.name))
        #expect(names.count == Internals.CookieStorage.maximumCookiesPerDomain)
        #expect(!names.contains("c0"))
        #expect(names.contains("c\(total - 1)"))
    }

    // MARK: - Public suffix

    @Test
    func store_whenDomainIsAPublicSuffix_rejectsTheCookie() throws {
        let list = try Internals.PublicSuffixList("com\nco.uk\n")
        let storage = Internals.CookieStorage(publicSuffixList: list)

        storage.store(setCookieValues: ["a=1; Domain=co.uk"], for: url("https://shop.co.uk/"), now: now)
        storage.store(setCookieValues: ["b=1; Domain=shop.co.uk"], for: url("https://www.shop.co.uk/"), now: now)

        #expect(storage.snapshot(now: now).map(\.name) == ["b"])
    }

    @Test
    func store_whenThereIsNoList_stillRejectsASingleLabelDomain() {
        let storage = Internals.CookieStorage()
        storage.store(setCookieValues: ["a=1; Domain=com"], for: url("https://example.com/"), now: now)

        #expect(storage.snapshot(now: now).isEmpty)
    }

    @Test
    func store_whenSingleLabelDomainIsTheHostItself_keepsItHostOnly() {
        let storage = Internals.CookieStorage()
        storage.store(setCookieValues: ["a=1; Domain=localhost"], for: url("http://localhost:8080/"), now: now)

        #expect(storage.snapshot(now: now).first?.hostOnly == true)
        #expect(header(storage, "http://localhost:8080/") == "a=1")
    }

    // MARK: - Folded headers

    @Test
    func store_whenSeveralCookiesAreFoldedIntoOneValue_storesEachOfThem() {
        let storage = Internals.CookieStorage()
        storage.store(
            setCookieValues: [
                "a=1; Expires=Wed, 01 Jan 2031 00:00:00 GMT; Path=/, b=2; Path=/, c=3"
            ],
            for: url("https://example.com/"),
            now: now
        )

        #expect(Set(storage.snapshot(now: now).map(\.name)) == ["a", "b", "c"])
        #expect(header(storage, "https://example.com/") == "a=1; b=2; c=3")
    }

    @Test
    func removeAll_clearsEveryCookie() {
        let storage = Internals.CookieStorage()
        storage.store(setCookieValues: ["a=1"], for: url("https://example.com/"), now: now)
        storage.removeAll()

        #expect(header(storage, "https://example.com/") == nil)
    }
}
