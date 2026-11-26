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
        // Among equal paths the oldest are left out, and in a tie the one stored first is the older.
        #expect(header.hasPrefix("c49="))
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

        // One more cookie does not fit beside them: the oldest is the one left out.
        storage.store(setCookieValues: ["c=1"], for: url("https://example.com/"), now: now)

        let after = try #require(storage.cookieHeader(for: url("https://example.com/"), now: now))

        #expect(after.utf8.count <= limit)
        #expect(after.hasSuffix("; c=1"))
        #expect(!after.hasPrefix("a="))
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

        // In the order a request to /a is sent: a, b, c, then d. The header is filled from the
        // other end (the longer path, then the newer one), so c and b fit and a does not, and d, which
        // would, is left out too: it could be the less specific cookie of a name the server would read
        // in place of one that was dropped.
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

        #expect(names == ["b", "c"])
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

        // `a`, the oldest, is the one left out.
        #expect(lastAccess["a"] == now)
        #expect(lastAccess["b"] == later)
        #expect(lastAccess["c"] == later)
    }

    @Test
    func cookieHeader_whenOverTheLimit_keepsTheCookieJustSetAndDropsTheOldest() throws {
        let storage = Internals.CookieStorage()
        let big = String(repeating: "x", count: 4_000)

        // A sibling subdomain sets two large cookies for the whole domain, then the login sets `sid`:
        // smaller and newer, with the same path. It is the one that must not be left out.
        storage.store(
            setCookieValues: ["b1=\(big); Domain=example.com", "b2=\(big); Domain=example.com"],
            for: url("https://evil.example.com/"),
            now: now
        )
        storage.store(
            setCookieValues: ["sid=SECRET"],
            for: url("https://example.com/"),
            now: now.addingTimeInterval(5)
        )

        let target = url("https://example.com/")
        let header = try #require(storage.cookieHeader(for: target, now: now.addingTimeInterval(10)))

        #expect(header.contains("sid=SECRET"))
        #expect(header.utf8.count <= limit)
        // The cookies still go in the order RFC 6265 gives: the older first.
        #expect(header.hasPrefix("b2="))
        #expect(
            storage.cookies(for: target, now: now.addingTimeInterval(10)).map(\.name) == ["b2", "sid"]
        )
    }

    // MARK: - Reporting what was left out

    private func storageWithTwoBigCookies(now: Date) -> Internals.CookieStorage {
        let storage = Internals.CookieStorage()
        let big = String(repeating: "x", count: 4_000)

        storage.store(
            setCookieValues: ["b1=\(big); Domain=example.com", "b2=\(big); Domain=example.com"],
            for: url("https://example.com/"),
            now: now
        )

        return storage
    }

    @Test
    func cookieHeaderReportingOmission_whenCookiesAreLeftOut_saysHowManyOnceAndNeverWhich() throws {
        let storage = storageWithTwoBigCookies(now: now)
        storage.store(setCookieValues: ["sid=SECRET"], for: url("https://example.com/"), now: now.addingTimeInterval(5))

        let target = url("https://example.com/")

        let first = storage.cookieHeaderReportingOmission(for: target, now: now.addingTimeInterval(10))
        let second = storage.cookieHeaderReportingOmission(for: target, now: now.addingTimeInterval(11))

        #expect(first.value == second.value)
        #expect(first.omission == .init(count: 1, host: "example.com", limit: limit))
        #expect(second.omission == nil)
    }

    @Test
    func cookieHeaderReportingOmission_whenNothingIsLeftOut_reportsNothing() throws {
        let storage = Internals.CookieStorage()
        storage.store(setCookieValues: ["a=1", "b=2"], for: url("https://example.com/"), now: now)

        let result = storage.cookieHeaderReportingOmission(for: url("https://example.com/"), now: now)

        #expect(result.value == "a=1; b=2")
        #expect(result.omission == nil)
    }

    @Test
    func cookieHeaderReportingOmission_whenTheCookiesLeftOutChange_reportsAgain() throws {
        let storage = storageWithTwoBigCookies(now: now)
        let target = url("https://example.com/")

        #expect(storage.cookieHeaderReportingOmission(for: target, now: now).omission?.count == 1)
        #expect(storage.cookieHeaderReportingOmission(for: target, now: now).omission == nil)

        // Another cookie that does not fit: the set that is left out is no longer the same.
        storage.store(
            setCookieValues: ["b3=\(String(repeating: "x", count: 4_000)); Domain=example.com"],
            for: target,
            now: now.addingTimeInterval(1)
        )

        #expect(storage.cookieHeaderReportingOmission(for: target, now: now.addingTimeInterval(2)).omission?.count == 2)
        #expect(storage.cookieHeaderReportingOmission(for: target, now: now.addingTimeInterval(2)).omission == nil)
    }

    @Test
    func cookieHeaderReportingOmission_whenItStopsAndStartsAgain_reportsAgain() throws {
        let storage = storageWithTwoBigCookies(now: now)
        let target = url("https://example.com/")

        #expect(storage.cookieHeaderReportingOmission(for: target, now: now).omission != nil)

        // A path the big cookies do not match leaves nothing out, which forgets the host's state.
        storage.removeAll(forHost: "example.com", includingSubdomains: true)
        #expect(storage.cookieHeaderReportingOmission(for: target, now: now).omission == nil)

        storage.store(
            setCookieValues: ["b1=\(String(repeating: "x", count: 4_000)); Domain=example.com"],
            for: target,
            now: now
        )
        storage.store(
            setCookieValues: ["b2=\(String(repeating: "x", count: 4_000)); Domain=example.com"],
            for: target,
            now: now
        )

        #expect(storage.cookieHeaderReportingOmission(for: target, now: now).omission != nil)
    }

    @Test
    func cookieHeader_neverChangesWhatWasReported() throws {
        let storage = storageWithTwoBigCookies(now: now)
        let target = url("https://example.com/")

        // A redirect hop asks without reporting, and must neither report nor use up the report.
        _ = storage.cookieHeader(for: target, now: now)

        #expect(storage.cookieHeaderReportingOmission(for: target, now: now).omission?.count == 1)
    }
}
