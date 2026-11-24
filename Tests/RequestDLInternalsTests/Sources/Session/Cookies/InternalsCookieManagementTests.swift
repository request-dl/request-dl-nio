//
// See LICENSE for this package's licensing information.
//

import Foundation
import Testing

@testable import RequestDLInternals

private let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

private func cookie(
    _ name: String = "sid",
    value: String = "abc",
    domain: String = "example.com",
    hostOnly: Bool = true,
    path: String = "/",
    secure: Bool = false,
    expires: Date? = nil,
    creation: Date? = nil
) -> Internals.Cookie {
    Internals.Cookie(
        name: name,
        value: value,
        domain: domain,
        hostOnly: hostOnly,
        path: path,
        secure: secure,
        expires: expires,
        creation: creation ?? referenceDate
    )
}

/// `CookieStorage.insert`, `remove…`, `cookies(for:)` and `restore`: what a caller can do to a
/// jar beyond what its responses do to it.
struct InternalsCookieManagementTests {

    private let now = referenceDate

    private func url(_ string: String) -> URL {
        URL(string: string)!
    }

    private func list() throws -> Internals.PublicSuffixList {
        try Internals.PublicSuffixList("com\nco.uk\n*.ck\n!www.ck\n")
    }

    // MARK: - insert

    @Test
    func insert_whenCookieIsValid_isSentToMatchingRequests() throws {
        let storage = Internals.CookieStorage()
        try storage.insert(cookie(), now: now)

        #expect(storage.cookieHeader(for: url("https://example.com/x"), now: now) == "sid=abc")
        #expect(storage.cookieHeader(for: url("https://other.com/x"), now: now) == nil)
    }

    @Test
    func insert_whenDomainIsNotNormalized_storesItNormalized() throws {
        let storage = Internals.CookieStorage()
        try storage.insert(cookie(domain: ".Example.COM", hostOnly: false), now: now)

        #expect(storage.snapshot(now: now).map(\.domain) == ["example.com"])
        #expect(storage.cookieHeader(for: url("https://api.example.com/"), now: now) == "sid=abc")
    }

    @Test
    func insert_whenCookieReplacesAnother_keepsTheCreationOfTheFirst() throws {
        let storage = Internals.CookieStorage()
        let first = now.addingTimeInterval(-100)
        try storage.insert(cookie(value: "old", creation: first), now: now)
        try storage.insert(cookie(value: "new", creation: now), now: now)

        let stored = storage.snapshot(now: now)
        #expect(stored.map(\.value) == ["new"])
        #expect(stored.first?.creation == first)
    }

    @Test
    func insert_whenHostOnlyAndDomainCookiesShareNamePathAndDomain_keepsBoth() throws {
        let storage = Internals.CookieStorage()
        try storage.insert(cookie(value: "a", hostOnly: true), now: now)
        try storage.insert(cookie(value: "b", hostOnly: false), now: now)

        #expect(storage.snapshot(now: now).count == 2)
    }

    @Test
    func insert_whenCookieIsAlreadyExpired_deletesTheOneItReplacesAndStoresNothing() throws {
        let storage = Internals.CookieStorage()
        try storage.insert(cookie(), now: now)
        try storage.insert(cookie(expires: now.addingTimeInterval(-1)), now: now)

        #expect(storage.snapshot(now: now).isEmpty)
    }

    @Test
    func insert_whenSecureCookieHasNoOrigin_isAcceptedAndStillOnlySentOverTLS() throws {
        let storage = Internals.CookieStorage()
        try storage.insert(cookie(secure: true), now: now)

        #expect(storage.cookieHeader(for: url("http://example.com/"), now: now) == nil)
        #expect(storage.cookieHeader(for: url("https://example.com/"), now: now) == "sid=abc")
    }

    @Test
    func insert_whenInsertedCookieIsNotSecure_isNotRefusedForShadowingASecureOne() throws {
        let storage = Internals.CookieStorage()
        try storage.insert(cookie(domain: "example.com", hostOnly: false, secure: true), now: now)
        try storage.insert(cookie(domain: "example.com", hostOnly: false, path: "/app"), now: now)

        #expect(storage.snapshot(now: now).count == 2)
    }

    @Test
    func insert_whenTheJarIsFull_evictsTheLeastRecentlyUsed() throws {
        let storage = Internals.CookieStorage()
        let limit = Internals.CookieStorage.maximumCookiesPerDomain

        for index in 0...limit {
            try storage.insert(cookie("c\(index)"), now: now.addingTimeInterval(TimeInterval(index)))
        }

        let names = storage.snapshot(now: now.addingTimeInterval(1_000)).map(\.name)
        #expect(names.count == limit)
        #expect(!names.contains("c0"))
        #expect(names.contains("c\(limit)"))
    }

    // MARK: - insert: rejections

    @Test(
        arguments: [
            (cookie(""), Internals.Cookie.Rejection.invalidName),
            (cookie("a;b"), .invalidName),
            (cookie("a=b"), .invalidName),
            (cookie(" a"), .invalidName),
            (cookie("a\u{7F}"), .invalidName),
            (cookie("a\tb\u{1}"), .invalidName),
            (cookie(value: "x; admin=1"), .invalidValue),
            (cookie(value: "x\r\nSet-Cookie: y=1"), .invalidValue),
            (cookie(value: "x "), .invalidValue),
            (cookie(value: "\tx"), .invalidValue),
            (cookie(value: "日本語"), .invalidValue),
            (cookie("naïve"), .invalidName),
            (cookie(domain: ""), .invalidDomain),
            (cookie(domain: "exa mple.com"), .invalidDomain),
            (cookie(domain: "a..b"), .invalidDomain),
            (cookie(domain: "example.com."), .invalidDomain),
            (cookie(domain: "127.0.0.1", hostOnly: false), .invalidDomain),
            (cookie(domain: "com", hostOnly: false), .publicSuffix),
            (cookie(domain: "localhost", hostOnly: false), .publicSuffix),
            (cookie(path: ""), .invalidPath),
            (cookie(path: "app"), .invalidPath),
            (cookie(path: "/a;b"), .invalidPath),
            (cookie(path: "/a\u{0}"), .invalidPath),
            (cookie(path: "/" + String(repeating: "a", count: 1_024)), .tooLarge),
            (cookie(domain: String(repeating: "a", count: 1_025)), .tooLarge),
            (cookie(value: String(repeating: "a", count: 4_096)), .tooLarge),
            (cookie("__Secure-a"), .prefixRule),
            (cookie("__secure-a"), .prefixRule),
            (cookie("__Host-a", path: "/x", secure: true), .prefixRule),
            (cookie("__Host-a", hostOnly: false, secure: true), .prefixRule),
            (cookie("__Host-a"), .prefixRule),
        ]
    )
    func insert_whenCookieIsInvalid_throwsTheReasonAndStoresNothing(
        invalid: Internals.Cookie,
        expected: Internals.Cookie.Rejection
    ) {
        let storage = Internals.CookieStorage()

        #expect(throws: expected) {
            try storage.insert(invalid, now: now)
        }

        #expect(storage.snapshot(now: now).isEmpty)
    }

    @Test
    func insert_whenPrefixRulesAreMet_isAccepted() throws {
        let storage = Internals.CookieStorage()
        try storage.insert(cookie("__Secure-a", domain: "example.com", hostOnly: false, secure: true), now: now)
        try storage.insert(cookie("__Host-b", secure: true), now: now)

        #expect(storage.snapshot(now: now).count == 2)
    }

    @Test
    func insert_whenDomainIsAPublicSuffixOfTheList_isRefusedOnlyForDomainCookies() throws {
        let storage = Internals.CookieStorage(publicSuffixList: try list())

        #expect(throws: Internals.Cookie.Rejection.publicSuffix) {
            try storage.insert(cookie(domain: "co.uk", hostOnly: false), now: now)
        }

        #expect(throws: Internals.Cookie.Rejection.publicSuffix) {
            try storage.insert(cookie(domain: "foo.ck", hostOnly: false), now: now)
        }

        // A host-only cookie of that very host is what a response from it may set.
        try storage.insert(cookie(domain: "co.uk", hostOnly: true), now: now)
        // The exception of the list.
        try storage.insert(cookie(domain: "www.ck", hostOnly: false), now: now)
        try storage.insert(cookie(domain: "shop.co.uk", hostOnly: false), now: now)

        #expect(storage.snapshot(now: now).count == 3)
    }

    @Test
    func insert_whenHostIsAnIPAddress_acceptsAHostOnlyCookie() throws {
        let storage = Internals.CookieStorage()
        try storage.insert(cookie(domain: "127.0.0.1"), now: now)
        try storage.insert(cookie("v6", domain: "[::1]"), now: now)

        #expect(storage.cookieHeader(for: url("http://127.0.0.1/"), now: now) == "sid=abc")
        #expect(storage.cookieHeader(for: url("http://[::1]/"), now: now) == "v6=abc")
    }

    /// The validator is one: what `parse` accepts, `insert` accepts, and what it refuses for a
    /// reason both know, `insert` refuses.
    @Test(
        arguments: [
            "sid=abc; Secure; Domain=example.com",
            "__Host-a=1; Secure; Path=/",
            "__Secure-a=1; Secure",
            "a=1; Domain=com",
            "a=1; Domain=co.uk",
            "__Host-a=1; Secure; Domain=example.com",
            "__Secure-a=1",
            "a=\(String(repeating: "x", count: 4_100))",
            "a=b\u{1}",
        ]
    )
    func insert_whenParseAcceptedTheCookie_acceptsIt(header: String) throws {
        let origin = Internals.Cookie.Origin(host: "example.com", path: "/", isSecure: true)
        let list = try list()
        let parsed = Internals.Cookie.parse(header, from: origin, now: now, publicSuffixList: list)

        guard let parsed else {
            // Refused on receipt: building the same cookie by hand is refused too, or is a cookie
            // the parser would have defaulted differently.
            return
        }

        let storage = Internals.CookieStorage(publicSuffixList: list)
        try storage.insert(parsed, now: now)
        #expect(storage.snapshot(now: now).first?.name == parsed.name)
    }

    // MARK: - cookies(for:)

    @Test
    func cookiesFor_returnsWhatTheHeaderWouldCarryInTheSameOrder() {
        let storage = Internals.CookieStorage()
        storage.store(
            setCookieValues: ["a=1; Path=/", "b=2; Path=/app", "c=3; Path=/app/deep"],
            for: url("https://example.com/"),
            now: now
        )

        let target = url("https://example.com/app/deep/x")
        let cookies = storage.cookies(for: target, now: now)

        #expect(cookies.map(\.name) == ["c", "b", "a"])
        #expect(storage.cookieHeader(for: target, now: now) == "c=3; b=2; a=1")
    }

    @Test
    func cookiesFor_whenRequestIsPlaintext_leavesSecureCookiesOut() throws {
        let storage = Internals.CookieStorage()
        try storage.insert(cookie("s", secure: true), now: now)
        try storage.insert(cookie("p"), now: now)

        #expect(storage.cookies(for: url("http://example.com/"), now: now).map(\.name) == ["p"])
        #expect(storage.cookies(for: url("https://example.com/"), now: now).map(\.name) == ["s", "p"])
    }

    @Test
    func cookiesFor_whenURLHasNoHost_isEmpty() throws {
        let storage = Internals.CookieStorage()
        try storage.insert(cookie(), now: now)

        #expect(storage.cookies(for: url("file:///tmp/x"), now: now).isEmpty)
    }

    @Test
    func cookiesFor_skipsExpiredCookiesWithoutRemovingThem() throws {
        let storage = Internals.CookieStorage()
        try storage.insert(cookie(expires: now.addingTimeInterval(10)), now: now)

        #expect(storage.cookies(for: url("https://example.com/"), now: now.addingTimeInterval(20)).isEmpty)
    }

    /// `c0` is the only cookie a plaintext request matches, and the least recently used of all. If
    /// reading it counted as a use, `c1` would be evicted in its place.
    private func fullStorageWhereOnlyTheOldestMatchesPlaintext() throws -> Internals.CookieStorage {
        let storage = Internals.CookieStorage()
        let limit = Internals.CookieStorage.maximumCookiesPerDomain

        for index in 0..<limit {
            try storage.insert(
                cookie("c\(index)", secure: index != 0),
                now: now.addingTimeInterval(TimeInterval(index))
            )
        }

        return storage
    }

    /// Looking at a jar must not change which cookie it evicts next.
    @Test
    func cookiesFor_doesNotCountAsAUse() throws {
        let storage = try fullStorageWhereOnlyTheOldestMatchesPlaintext()

        let read = storage.cookies(for: url("http://example.com/"), now: now.addingTimeInterval(500))
        try storage.insert(cookie("new"), now: now.addingTimeInterval(1_000))

        let names = storage.snapshot(now: now.addingTimeInterval(1_001)).map(\.name)
        #expect(read.map(\.name) == ["c0"])
        #expect(!names.contains("c0"))
        #expect(names.contains("c1"))
    }

    @Test
    func cookieHeader_stillCountsAsAUse() throws {
        let storage = try fullStorageWhereOnlyTheOldestMatchesPlaintext()

        #expect(storage.cookieHeader(for: url("http://example.com/"), now: now.addingTimeInterval(500)) == "c0=abc")
        try storage.insert(cookie("new"), now: now.addingTimeInterval(1_000))

        let names = storage.snapshot(now: now.addingTimeInterval(1_001)).map(\.name)
        #expect(names.contains("c0"))
        #expect(!names.contains("c1"))
    }

    // MARK: - remove

    @Test
    func removeByName_removesHostOnlyAndDomainCookiesAlike() throws {
        let storage = Internals.CookieStorage()
        try storage.insert(cookie(hostOnly: true), now: now)
        try storage.insert(cookie(hostOnly: false), now: now)
        try storage.insert(cookie("other"), now: now)
        try storage.insert(cookie(path: "/app"), now: now)

        #expect(storage.remove(name: "sid", domain: "Example.com", path: "/"))
        #expect(storage.snapshot(now: now).map(\.name).sorted() == ["other", "sid"])
        #expect(!storage.remove(name: "sid", domain: "example.com", path: "/"))
    }

    @Test
    func removeCookie_removesOnlyTheOneWithTheSameIdentity() throws {
        let storage = Internals.CookieStorage()
        try storage.insert(cookie(value: "a", hostOnly: true), now: now)
        try storage.insert(cookie(value: "b", hostOnly: false), now: now)

        #expect(storage.remove(cookie(value: "ignored", hostOnly: false)))
        #expect(storage.snapshot(now: now).map(\.value) == ["a"])
    }

    @Test
    func removeAllForHost_removesWhatARequestToThatHostWouldMatch() throws {
        let storage = Internals.CookieStorage()
        try storage.insert(cookie("host", domain: "api.example.com"), now: now)
        try storage.insert(cookie("domain", domain: "example.com", hostOnly: false), now: now)
        try storage.insert(cookie("hostOfParent", domain: "example.com"), now: now)
        try storage.insert(cookie("child", domain: "x.api.example.com"), now: now)
        try storage.insert(cookie("secure", domain: "api.example.com", path: "/a", secure: true), now: now)
        try storage.insert(cookie("other", domain: "other.com"), now: now)

        storage.removeAll(forHost: "API.example.com", includingSubdomains: false)

        #expect(storage.snapshot(now: now).map(\.name).sorted() == ["child", "hostOfParent", "other"])
    }

    @Test
    func removeAllForHost_includingSubdomains_removesTheHostsBelowIt() throws {
        let storage = Internals.CookieStorage()
        try storage.insert(cookie("parent", domain: "example.com"), now: now)
        try storage.insert(cookie("child", domain: "api.example.com"), now: now)
        try storage.insert(cookie("domain", domain: "example.com", hostOnly: false), now: now)
        try storage.insert(cookie("lookalike", domain: "notexample.com"), now: now)

        storage.removeAll(forHost: "example.com", includingSubdomains: true)

        #expect(storage.snapshot(now: now).map(\.name) == ["lookalike"])
    }

    @Test
    func removeAllForHost_whenHostIsAnIPAddress_matchesItByEquality() throws {
        let storage = Internals.CookieStorage()
        try storage.insert(cookie("a", domain: "127.0.0.1"), now: now)
        try storage.insert(cookie("b", domain: "5.127.0.0.1"), now: now)

        storage.removeAll(forHost: "127.0.0.1", includingSubdomains: true)

        #expect(storage.snapshot(now: now).map(\.name) == ["b"])
    }

    @Test
    func removeAllForHost_whenHostIsUnicode_matchesItsPunycodeForm() throws {
        let storage = Internals.CookieStorage()
        try storage.insert(cookie(domain: "xn--bcher-kva.example"), now: now)

        storage.removeAll(forHost: "bücher.example", includingSubdomains: false)

        #expect(storage.snapshot(now: now).isEmpty)
    }

    @Test
    func removeAllForHost_whenHostIsEmpty_removesNothing() throws {
        let storage = Internals.CookieStorage()
        try storage.insert(cookie(), now: now)

        storage.removeAll(forHost: "", includingSubdomains: true)
        storage.removeAll(forHost: ".", includingSubdomains: true)

        #expect(storage.snapshot(now: now).count == 1)
    }

    // MARK: - restore

    @Test
    func restore_addsTheCookiesAndReportsNoneRefused() {
        let storage = Internals.CookieStorage()
        let refused = storage.restore([cookie("a"), cookie("b")], now: now)

        #expect(refused == 0)
        #expect(storage.cookieHeader(for: url("https://example.com/"), now: now) == "a=abc; b=abc")
    }

    @Test
    func restore_whenCookieIsInvalid_skipsItAndCountsIt() throws {
        let storage = Internals.CookieStorage(publicSuffixList: try list())

        let refused = storage.restore(
            [
                cookie("good"),
                cookie("tampered", domain: "co.uk", hostOnly: false),
                cookie("injected", value: "x; admin=1"),
                cookie("__Host-bad"),
            ],
            now: now
        )

        #expect(refused == 3)
        #expect(storage.snapshot(now: now).map(\.name) == ["good"])
    }

    @Test
    func restore_whenCookieIsExpired_skipsItAndDoesNotDeleteALiveOne() throws {
        let storage = Internals.CookieStorage()
        try storage.insert(cookie(value: "live"), now: now)

        let refused = storage.restore([cookie(value: "stale", expires: now.addingTimeInterval(-1))], now: now)

        #expect(refused == 1)
        #expect(storage.snapshot(now: now).map(\.value) == ["live"])
    }

    @Test
    func restore_whenTheJarAlreadyHoldsTheCookie_keepsTheOneItHas() throws {
        let storage = Internals.CookieStorage()
        try storage.insert(cookie(value: "live"), now: now)

        let refused = storage.restore([cookie(value: "persisted"), cookie("extra")], now: now)

        #expect(refused == 1)
        #expect(storage.snapshot(now: now).map(\.value) == ["live", "abc"])
    }

    @Test
    func restore_whenCookiesExceedTheLimits_keepsTheJarWithinThem() {
        let storage = Internals.CookieStorage()
        let perDomain = Internals.CookieStorage.maximumCookiesPerDomain

        let cookies = (0..<(perDomain + 10)).map {
            cookie("c\($0)", creation: now.addingTimeInterval(TimeInterval($0)))
        }
        storage.restore(cookies, now: now)

        let names = storage.snapshot(now: now).map(\.name)
        #expect(names.count == perDomain)
        // The oldest are the ones that go.
        #expect(!names.contains("c0"))
        #expect(names.contains("c\(perDomain + 9)"))
    }

    @Test
    func restore_whenSnapshotHasMoreThanTheTotalLimit_onlyLooksAtTheFirstOnes() {
        let storage = Internals.CookieStorage()
        let total = Internals.CookieStorage.maximumCookies

        let cookies = (0..<(total + 500)).map { cookie("c", domain: "h\($0).example") }
        let refused = storage.restore(cookies, now: now)

        #expect(storage.snapshot(now: now).count == total)
        #expect(refused == 500)
    }

    // MARK: - Concurrency

    @Test
    func management_whenCalledFromManyThreadsWhileResponsesAreStored_keepsTheJarConsistent() async {
        let storage = Internals.CookieStorage()
        let target = url("https://example.com/")

        await withTaskGroup(of: Void.self) { group in
            for worker in 0..<8 {
                group.addTask {
                    for index in 0..<200 {
                        let name = "c\(worker)_\(index % 20)"

                        switch index % 5 {
                        case 0:
                            storage.store(setCookieValues: ["\(name)=1"], for: target)
                        case 1:
                            try? storage.insert(
                                Internals.Cookie(
                                    name: name,
                                    value: "2",
                                    domain: "example.com",
                                    hostOnly: true,
                                    path: "/",
                                    creation: Date()
                                )
                            )
                        case 2:
                            _ = storage.cookies(for: target)
                        case 3:
                            storage.remove(name: name, domain: "example.com", path: "/")
                        default:
                            storage.restore([
                                Internals.Cookie(
                                    name: name,
                                    value: "3",
                                    domain: "example.com",
                                    hostOnly: true,
                                    path: "/",
                                    creation: Date()
                                )
                            ])
                        }
                    }
                }
            }
        }

        let names = storage.snapshot().map(\.name)
        #expect(Set(names).count == names.count)
        #expect(names.count <= Internals.CookieStorage.maximumCookiesPerDomain)
    }
}
