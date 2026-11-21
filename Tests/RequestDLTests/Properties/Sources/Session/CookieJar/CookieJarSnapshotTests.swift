//
// See LICENSE for this package's licensing information.
//

import Foundation
import Testing

@testable import RequestDL

/// The value types of the jar's public API, which need no server: what `CookieJar.Cookie` and
/// `CookieJar.Snapshot` encode, describe, convert to, and refuse.
struct CookieJarSnapshotTests {

    private static let secret = "s3cr3t-session-token"

    private let expires = Date(timeIntervalSince1970: 1_800_000_000)
    private let creation = Date(timeIntervalSince1970: 1_700_000_000.25)

    private func cookie(
        _ name: String = "sid",
        value: String = CookieJarSnapshotTests.secret,
        expires: Date? = nil
    ) -> CookieJar.Cookie {
        CookieJar.Cookie(
            name: name,
            value: value,
            domain: "example.com",
            hostOnly: false,
            path: "/app",
            secure: true,
            httpOnly: true,
            expires: expires ?? self.expires,
            creation: creation
        )
    }

    // MARK: - Reading and the jar

    @Test
    func cookies_returnsCopiesOfWhatWasInserted() throws {
        let jar = CookieJar()
        let inserted = cookie(value: "v")
        try jar.insert(inserted)

        #expect(jar.cookies == [inserted])
        #expect(jar.cookies(for: URL(string: "https://api.example.com/app/x")!) == [inserted])
        #expect(jar.cookies(for: URL(string: "https://api.example.com/other")!).isEmpty)
    }

    @Test
    func insert_whenCookieIsRefused_throwsTheMatchingErrorAndLeavesTheJarAsItWas() throws {
        let jar = CookieJar()
        try jar.insert(cookie("kept", value: "1"))

        let cases: [(CookieJar.Cookie, CookieJarError)] = [
            (cookie("a;b"), .invalidName),
            (cookie(value: "x; admin=1"), .invalidValue),
            (CookieJar.Cookie(name: "a", value: "b", domain: "bad host"), .invalidDomain),
            (CookieJar.Cookie(name: "a", value: "b", domain: "example.com", path: "rel"), .invalidPath),
            (cookie(value: String(repeating: "x", count: 5_000)), .tooLarge),
            (CookieJar.Cookie(name: "a", value: "b", domain: "com", hostOnly: false), .publicSuffix),
            (CookieJar.Cookie(name: "__Host-a", value: "b", domain: "example.com"), .prefixRule),
        ]

        for (refused, expected) in cases {
            #expect(throws: expected) {
                try jar.insert(refused)
            }
        }

        #expect(jar.cookies.map(\.name) == ["kept"])
    }

    @Test
    func insert_whenJarHasAPublicSuffixList_refusesItsSuffixes() throws {
        let list = try PublicSuffixList(data: Data("com\nco.uk\n".utf8))
        let jar = CookieJar(publicSuffixList: list)

        #expect(throws: CookieJarError.publicSuffix) {
            try jar.insert(CookieJar.Cookie(name: "a", value: "b", domain: "co.uk", hostOnly: false))
        }

        try jar.insert(CookieJar.Cookie(name: "a", value: "b", domain: "shop.co.uk", hostOnly: false))
    }

    @Test
    func remove_whenCookieIsGiven_removesTheOneWithItsIdentity() throws {
        let jar = CookieJar()
        let stored = cookie()
        try jar.insert(stored)

        var changed = stored
        changed.value = "other"

        #expect(jar.remove(changed))
        #expect(jar.cookies.isEmpty)
        #expect(!jar.remove(changed))
    }

    // MARK: - Snapshot

    @Test
    func snapshot_leavesSessionAndExpiredCookiesOutByDefault() throws {
        let jar = CookieJar()
        try jar.insert(cookie("persistent"))
        try jar.insert(
            CookieJar.Cookie(name: "session", value: "1", domain: "example.com", expires: nil)
        )
        try jar.insert(cookie("soon", expires: Date(timeIntervalSinceNow: 0.05)))

        #expect(jar.snapshot().cookies.map(\.name).sorted() == ["persistent", "soon"])
        #expect(
            jar.snapshot(includingSessionCookies: true).cookies.map(\.name).sorted() == [
                "persistent", "session", "soon",
            ]
        )
    }

    @Test
    func snapshot_roundTripsThroughJSON_withDatesAtTheirOwnPrecision() throws {
        let snapshot = CookieJar.Snapshot(cookies: [cookie("a"), cookie("b", value: "é\"'")])

        let decoded = try JSONDecoder().decode(CookieJar.Snapshot.self, from: JSONEncoder().encode(snapshot))

        #expect(decoded == snapshot)
        #expect(decoded.cookies.first?.creation == creation)
    }

    /// A snapshot written with one date strategy must not shift expiries when read with another.
    @Test
    func snapshot_ignoresTheDateStrategyOfTheEncoderAndTheDecoder() throws {
        let snapshot = CookieJar.Snapshot(cookies: [cookie()])

        let iso = JSONEncoder()
        iso.dateEncodingStrategy = .iso8601
        let millis = JSONDecoder()
        millis.dateDecodingStrategy = .millisecondsSince1970

        let decoded = try millis.decode(CookieJar.Snapshot.self, from: iso.encode(snapshot))

        #expect(decoded == snapshot)
    }

    @Test
    func snapshot_hasAVersionAndRefusesANewerOne() throws {
        let json = try String(decoding: JSONEncoder().encode(CookieJar.Snapshot(cookies: [])), as: UTF8.self)
        #expect(json.contains("\"version\":1"))

        let newer = Data(#"{"version":2,"cookies":[]}"#.utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(CookieJar.Snapshot.self, from: newer)
        }

        let missing = Data(#"{"cookies":[]}"#.utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(CookieJar.Snapshot.self, from: missing)
        }
    }

    @Test
    func restore_withATamperedSnapshot_skipsWhatTheJarWouldRefuse() throws {
        let tampered = #"""
            {"version":1,"cookies":[
              {"name":"ok","value":"1","domain":"example.com","hostOnly":true,"path":"/","secure":false,
               "httpOnly":false,"expires":1900000000,"creation":1700000000},
              {"name":"super","value":"1","domain":"com","hostOnly":false,"path":"/","secure":false,
               "httpOnly":false,"expires":1900000000,"creation":1700000000},
              {"name":"inject","value":"x; admin=1","domain":"example.com","hostOnly":true,"path":"/","secure":false,
               "httpOnly":false,"expires":1900000000,"creation":1700000000},
              {"name":"old","value":"1","domain":"example.com","hostOnly":true,"path":"/","secure":false,
               "httpOnly":false,"expires":1000000000,"creation":900000000}
            ]}
            """#

        let snapshot = try JSONDecoder().decode(CookieJar.Snapshot.self, from: Data(tampered.utf8))
        let jar = CookieJar()
        let refused = jar.restore(snapshot)

        #expect(refused == 3)
        #expect(jar.cookies.map(\.name) == ["ok"])
    }

    @Test
    func restore_doesNotReplaceACookieTheJarHolds() throws {
        let jar = CookieJar()
        try jar.insert(cookie(value: "live"))

        let refused = jar.restore(CookieJar.Snapshot(cookies: [cookie(value: "persisted")]))

        #expect(refused == 1)
        #expect(jar.cookies.map(\.value) == ["live"])
    }

    @Test
    func initRestoring_usesThePublicSuffixListItWasGiven() throws {
        let list = try PublicSuffixList(data: Data("com\nco.uk\n".utf8))
        let snapshot = CookieJar.Snapshot(
            cookies: [CookieJar.Cookie(name: "a", value: "b", domain: "co.uk", hostOnly: false, expires: expires)]
        )

        #expect(CookieJar(restoring: snapshot).cookies.count == 1)
        #expect(CookieJar(restoring: snapshot, publicSuffixList: list).cookies.isEmpty)
    }

    // MARK: - Observing

    @Test
    func changes_signalsEachKindOfChangeAndNotWhatIsNot() async throws {
        let jar = CookieJar()
        var iterator = jar.changes.makeAsyncIterator()

        try jar.insert(cookie())
        #expect(await iterator.next() != nil)

        jar.remove(cookie())
        #expect(await iterator.next() != nil)

        jar.restore(CookieJar.Snapshot(cookies: [cookie()]))
        #expect(await iterator.next() != nil)

        jar.removeAll(forHost: "example.com")
        #expect(await iterator.next() != nil)

        try jar.insert(cookie())
        #expect(await iterator.next() != nil)

        jar.removeAll()
        #expect(await iterator.next() != nil)

        // None of these is a change, so the next element is the one of the insert after them.
        jar.removeAll()
        jar.remove(cookie())
        try jar.insert(cookie("last"))
        _ = jar.cookies
        _ = jar.snapshot()
        #expect(await iterator.next() != nil)
        #expect(jar.cookies.map(\.name) == ["last"])
    }

    @Test
    func changes_whenTheJarIsReleased_theStreamEnds() async throws {
        var jar: CookieJar? = CookieJar()
        let stream = try #require(jar?.changes)

        try jar?.insert(cookie())
        jar = nil

        var count = 0
        for await _ in stream {
            count += 1
        }

        #expect(count == 1)
    }

    // MARK: - Never in logs

    @Test
    func descriptions_neverContainTheValue() throws {
        let cookie = cookie()
        let snapshot = CookieJar.Snapshot(cookies: [cookie])

        var dumped = ""
        dump(cookie, to: &dumped)
        dump(snapshot, to: &dumped)

        let texts = [
            "\(cookie)",
            String(describing: cookie),
            String(reflecting: cookie),
            "\(snapshot)",
            String(reflecting: snapshot),
            "\([cookie])",
            "\(CookieJar.Cookie?.some(cookie) as Any)",
            dumped,
        ]

        for text in texts {
            #expect(!text.contains(Self.secret))
        }

        #expect(String(describing: cookie).contains("<redacted>"))
        #expect(String(describing: cookie).contains("sid"))
        #expect(String(describing: snapshot).contains("1"))
    }

    @Test(arguments: [
        CookieJarError.invalidName, .invalidValue, .invalidDomain, .invalidPath, .tooLarge, .publicSuffix, .prefixRule,
    ])
    func errors_describeWithoutAnyCookie(error: CookieJarError) throws {
        let jar = CookieJar()

        let refused = CookieJar.Cookie(name: "a;b", value: Self.secret, domain: "example.com")
        let thrown = #expect(throws: CookieJarError.self) {
            try jar.insert(refused)
        }

        #expect(thrown != nil)
        #expect(!"\(error)".contains(Self.secret))
        #expect(!"\(thrown as Any)".contains(Self.secret))
        #expect(!String(reflecting: thrown as Any).contains(Self.secret))
    }

    // MARK: - HTTPCookie

    #if canImport(Darwin)

    @Test
    func httpCookie_roundTripsTheFieldsItCarries() throws {
        let original = cookie()

        let converted = try #require(original.httpCookie)
        let back = CookieJar.Cookie(converted)

        #expect(converted.domain == ".example.com")
        #expect(converted.isSecure)
        #expect(converted.isHTTPOnly)
        #expect(!converted.isSessionOnly)
        #expect(back.name == original.name)
        #expect(back.value == original.value)
        #expect(back.domain == "example.com")
        #expect(!back.hostOnly)
        #expect(back.path == original.path)
        #expect(back.secure && back.httpOnly)
        #expect(back.expires == original.expires)
    }

    @Test
    func httpCookie_forAHostOnlySessionCookie_hasNoDotAndNoExpiry() throws {
        let original = CookieJar.Cookie(name: "a", value: "b", domain: "example.com")

        let converted = try #require(original.httpCookie)
        let back = CookieJar.Cookie(converted)

        #expect(converted.domain == "example.com")
        #expect(converted.isSessionOnly)
        #expect(back.hostOnly)
        #expect(back.expires == nil)
    }

    @Test
    func initFromHTTPCookie_stillGoesThroughTheJarsChecks() throws {
        let hostile = try #require(
            HTTPCookie(properties: [.name: "a", .value: "b", .domain: ".com", .path: "/"])
        )

        #expect(throws: CookieJarError.publicSuffix) {
            try CookieJar().insert(CookieJar.Cookie(hostile))
        }
    }

    #endif
}
