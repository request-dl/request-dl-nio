//
// See LICENSE for this package's licensing information.
//

import Foundation
import Testing

@testable import RequestDLInternals

/// `https://evil.com./` is the same host as `https://evil.com/`. A trailing dot must not make a
/// single-label `Domain` (`com.`) look like more than one label, or hide a public suffix
/// (`co.uk.`) from the list.
struct InternalsCookieTrailingDotTests {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func url(_ string: String) -> URL {
        URL(string: string)!
    }

    private func parse(
        _ header: String,
        host: String,
        list: Internals.PublicSuffixList? = nil
    ) -> Internals.Cookie? {
        Internals.Cookie.parse(
            header,
            from: .init(host: host, path: "/", isSecure: true),
            now: now,
            publicSuffixList: list
        )
    }

    // MARK: - domainMatches

    @Test
    func domainMatches_whenEitherEndsWithADot_neverMatches() {
        #expect(!Internals.Cookie.domainMatches(host: "evil.com.", domain: "com."))
        #expect(!Internals.Cookie.domainMatches(host: "evil.com", domain: "com."))
        #expect(!Internals.Cookie.domainMatches(host: "evil.com.", domain: "com"))
        #expect(!Internals.Cookie.domainMatches(host: "example.com.", domain: "example.com."))
        #expect(Internals.Cookie.domainMatches(host: "evil.com", domain: "com"))
    }

    // MARK: - parse

    @Test
    func parse_whenDomainIsASingleLabelWithATrailingDot_rejectsIt() {
        #expect(parse("sid=attacker; Domain=com.", host: "evil.com") == nil)
        #expect(parse("sid=attacker; Domain=com.", host: "evil.com.") == nil)
        #expect(parse("sid=attacker; Domain=.com.", host: "evil.com.") == nil)
    }

    @Test
    func parse_whenDomainIsAPublicSuffixWithATrailingDot_rejectsIt() throws {
        let list = try Internals.PublicSuffixList("com\nco.uk\n")

        #expect(parse("a=1; Domain=co.uk.", host: "shop.co.uk", list: list) == nil)
        #expect(parse("a=1; Domain=co.uk.", host: "shop.co.uk.", list: list) == nil)
    }

    @Test
    func parse_whenDomainHasAnEmptyLabel_rejectsIt() {
        #expect(parse("a=1; Domain=example..com", host: "www.example..com") == nil)
        #expect(parse("a=1; Domain=com..", host: "evil.com") == nil)
    }

    @Test
    func parse_whenDomainIsTheHostWithATrailingDot_storesTheNameWithoutIt() {
        let cookie = parse("a=1; Domain=example.com.", host: "www.example.com")

        #expect(cookie?.domain == "example.com")
        #expect(cookie?.hostOnly == false)
    }

    // MARK: - CookieStorage

    @Test
    func store_whenAFullyQualifiedHostSetsADomainOfTheTLD_cannotFixateAnotherSitesSession() {
        let storage = Internals.CookieStorage()

        storage.store(
            setCookieValues: ["sid=attacker; Domain=com."],
            for: url("https://evil.com./"),
            now: now
        )

        #expect(storage.snapshot(now: now).isEmpty)
        #expect(storage.cookieHeader(for: url("https://bank.com./login"), now: now) == nil)
        #expect(storage.cookieHeader(for: url("https://bank.com/login"), now: now) == nil)
    }

    @Test
    func store_whenAFullyQualifiedHostSetsAPublicSuffixWithTheList_refusesIt() throws {
        let storage = Internals.CookieStorage(publicSuffixList: try .init("com\nco.uk\n"))

        storage.store(
            setCookieValues: ["sid=attacker; Domain=co.uk."],
            for: url("https://evil.co.uk./"),
            now: now
        )

        #expect(storage.snapshot(now: now).isEmpty)
    }

    @Test
    func store_whenTheHostHasATrailingDot_isTheSameHostWithoutIt() {
        let storage = Internals.CookieStorage()

        storage.store(setCookieValues: ["sid=abc"], for: url("https://example.com./login"), now: now)

        #expect(storage.snapshot(now: now).first?.domain == "example.com")
        #expect(storage.cookieHeader(for: url("https://example.com/"), now: now) == "sid=abc")
        #expect(storage.cookieHeader(for: url("https://example.com./"), now: now) == "sid=abc")
    }

    @Test
    func store_whenALegitimateDomainHasATrailingDot_stillSharesItWithSubdomains() {
        let storage = Internals.CookieStorage()

        storage.store(
            setCookieValues: ["sid=abc; Domain=example.com."],
            for: url("https://www.example.com./"),
            now: now
        )

        #expect(storage.cookieHeader(for: url("https://api.example.com/"), now: now) == "sid=abc")
    }

    // MARK: - insert, restore and remove

    @Test
    func insert_whenDomainIsASingleLabelWithATrailingDot_isRefusedForItsEmptyLabel() {
        let storage = Internals.CookieStorage()
        let cookie = Internals.Cookie(
            name: "a",
            value: "1",
            domain: "com.",
            hostOnly: false,
            path: "/",
            creation: now
        )

        #expect(throws: Internals.Cookie.Rejection.invalidDomain) {
            try storage.insert(cookie, now: now)
        }
    }

    @Test
    func insert_whenDomainIsAPublicSuffixWithATrailingDot_isRefusedForItsEmptyLabel() throws {
        let storage = Internals.CookieStorage(publicSuffixList: try .init("co.uk\n"))
        let cookie = Internals.Cookie(
            name: "a",
            value: "1",
            domain: "co.uk.",
            hostOnly: false,
            path: "/",
            creation: now
        )

        #expect(throws: Internals.Cookie.Rejection.invalidDomain) {
            try storage.insert(cookie, now: now)
        }
    }

    @Test
    func restore_whenDomainIsASingleLabelWithATrailingDot_skipsIt() {
        let storage = Internals.CookieStorage()
        let cookie = Internals.Cookie(
            name: "a",
            value: "1",
            domain: "com.",
            hostOnly: false,
            path: "/",
            creation: now
        )

        #expect(storage.restore([cookie], now: now) == 1)
        #expect(storage.snapshot(now: now).isEmpty)
    }

    @Test
    func removeAll_whenHostHasATrailingDot_removesTheCookiesOfThatHost() {
        let storage = Internals.CookieStorage()
        storage.store(setCookieValues: ["a=1"], for: url("https://example.com/"), now: now)

        storage.removeAll(forHost: "example.com.", includingSubdomains: false)

        #expect(storage.snapshot(now: now).isEmpty)
    }
}
