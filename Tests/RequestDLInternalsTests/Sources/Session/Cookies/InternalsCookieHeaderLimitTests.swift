//
// See LICENSE for this package's licensing information.
//

import Foundation
import Testing

@testable import RequestDLInternals

struct InternalsCookieHeaderLimitTests {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let limit = Internals.CookieStorage.maximumCookieHeaderLength

    private func url(_ string: String) -> URL {
        URL(string: string)!
    }

    /// A `Set-Cookie` value whose `name=value` has `size` bytes.
    private func setCookie(_ name: String, size: Int, attributes: String = "") -> String {
        "\(name)=\(String(repeating: "x", count: size - name.utf8.count - 1))\(attributes)"
    }

    @Test
    func maximumCookieHeaderLength_holdsTheLargestCookieAndIsUnderTheCommonServerLimit() {
        #expect(limit >= Internals.Cookie.maximumNameValueLength)
        #expect(limit < 8_190)
    }

    @Test
    func cookieHeader_whenAHostSetsFiftyLargeCookies_staysWithinTheLimit() throws {
        let storage = Internals.CookieStorage()

        // Fits the per-response and the per-domain limits: 50 cookies of 4 KB each, 200 KB.
        let values = (0..<50).map {
            setCookie("c\(String(format: "%02d", $0))", size: 4_096, attributes: "; Domain=example.com")
        }

        storage.store(
            setCookieValues: values,
            for: url("https://x.example.com/"),
            now: now
        )

        #expect(storage.snapshot(now: now).count == 50)

        let header = try #require(storage.cookieHeader(for: url("https://api.example.com/"), now: now))

        #expect(header.utf8.count <= limit)
        // The ones set first (the older, in a tie) are the ones kept.
        #expect(header.hasPrefix("c00="))
        #expect(header.split(separator: ";").count == 1)
    }

    @Test
    func cookieHeader_whenCookiesAreSmall_sendsAllOfThemAsBefore() throws {
        let storage = Internals.CookieStorage()

        storage.store(
            setCookieValues: (0..<50).map { "c\(String(format: "%02d", $0))=\($0)" },
            for: url("https://example.com/"),
            now: now
        )

        let header = try #require(storage.cookieHeader(for: url("https://example.com/"), now: now))

        #expect(header.split(separator: ";").count == 50)
        #expect(header.utf8.count < limit)
    }

    @Test
    func cookieHeader_whenAHeaderOfExactlyTheLimitIsBuilt_keepsEveryCookie() throws {
        let storage = Internals.CookieStorage()

        // Two cookies and the "; " between them are exactly `limit` bytes.
        let first = (limit - 2) / 2
        let second = limit - 2 - first

        storage.store(
            setCookieValues: [setCookie("a", size: first), setCookie("b", size: second)],
            for: url("https://example.com/"),
            now: now
        )

        let header = try #require(storage.cookieHeader(for: url("https://example.com/"), now: now))

        #expect(header.utf8.count == limit)
        #expect(header.split(separator: ";").count == 2)

        storage.store(setCookieValues: ["c=1"], for: url("https://example.com/"), now: now)

        #expect(storage.cookieHeader(for: url("https://example.com/"), now: now)?.utf8.count == limit)
    }

    @Test
    func cookieHeader_whenOverTheLimit_dropsTheCookiesWithTheShortestPaths() throws {
        let storage = Internals.CookieStorage()
        let origin = url("https://example.com/")

        // Created first, but the least specific for a request to /a/b.
        storage.store(setCookieValues: [setCookie("r", size: 3_900, attributes: "; Path=/")], for: origin, now: now)
        storage.store(setCookieValues: [setCookie("a", size: 3_900, attributes: "; Path=/a")], for: origin, now: now)
        storage.store(setCookieValues: [setCookie("b", size: 3_900, attributes: "; Path=/a/b")], for: origin, now: now)

        let target = url("https://example.com/a/b")
        let header = try #require(storage.cookieHeader(for: target, now: now))
        let names = header.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces).prefix(1) }

        #expect(names == ["b", "a"])
        #expect(storage.cookies(for: target, now: now).map(\.name) == ["b", "a"])
    }

    @Test
    func cookieHeader_whenOverTheLimit_stopsAtTheFirstCookieThatDoesNotFit() throws {
        let storage = Internals.CookieStorage()
        let origin = url("https://example.com/a")

        // In the order a request to /a is sent: a, b, c, then d. c does not fit, and d, which would,
        // is left out too: it could be the less specific cookie of a name the server would read in
        // place of one that was dropped.
        storage.store(
            setCookieValues: [
                setCookie("a", size: 3_900, attributes: "; Path=/a"),
                setCookie("b", size: 3_900, attributes: "; Path=/a"),
                setCookie("c", size: 3_900, attributes: "; Path=/a"),
                "d=1; Path=/",
            ],
            for: origin,
            now: now
        )

        let header = try #require(storage.cookieHeader(for: origin, now: now))
        let names = header.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces).prefix(1) }

        #expect(names == ["a", "b"])
    }

    @Test
    func cookieHeader_whenACookieIsLeftOut_doesNotCountItAsUsed() throws {
        let storage = Internals.CookieStorage()
        let origin = url("https://example.com/a")
        let later = now.addingTimeInterval(60)

        storage.store(
            setCookieValues: [
                setCookie("a", size: 3_900, attributes: "; Path=/a"),
                setCookie("b", size: 3_900, attributes: "; Path=/a"),
                setCookie("c", size: 3_900, attributes: "; Path=/a"),
            ],
            for: origin,
            now: now
        )

        _ = storage.cookieHeader(for: origin, now: later)

        let lastAccess = Dictionary(uniqueKeysWithValues: storage.snapshot(now: later).map { ($0.name, $0.lastAccess) })

        #expect(lastAccess["a"] == later)
        #expect(lastAccess["b"] == later)
        #expect(lastAccess["c"] == now)
    }
}
