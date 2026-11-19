//
// See LICENSE for this package's licensing information.
//

@_spi(Testing) import RequestDLInternals
import Testing

@testable import RequestDL

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.URL
#endif

/// The requests a resumable upload derives from the one it was given (create the upload, ask how
/// far it got, send the next part) may go to another path or, when the server chooses where the
/// upload lives, another origin. The jar answers for the host each of them goes to.
struct CookieJarResumableUploadTests {

    private func storage() throws -> Internals.CookieStorage {
        let storage = Internals.CookieStorage()
        let upload = try #require(URL(string: "https://upload.example.com/"))
        let cdn = try #require(URL(string: "https://cdn.example.org/"))

        storage.store(setCookieValues: ["a=1"], for: upload)
        storage.store(setCookieValues: ["b=2"], for: cdn)
        return storage
    }

    private func request(
        _ storage: Internals.CookieStorage,
        managesHeader: Bool,
        cookie: String
    ) -> RequestConfiguration {
        var request = RequestConfiguration()
        request.exactURL = "https://upload.example.com/files"
        request.headers.add(name: "Cookie", value: cookie)
        request.cookies = .init(storage: storage, managesHeader: managesHeader)
        return request
    }

    @Test
    func derived_whenTheJarOwnsTheHeader_replacesAStaleOneWithWhatTheJarHoldsNow() throws {
        let request = request(try storage(), managesHeader: true, cookie: "stale=1")

        let derived = request.derived(method: "PATCH", url: "https://upload.example.com/files/abc")

        #expect(derived.headers["Cookie"] == ["a=1"])
    }

    @Test
    func derived_whenTheJarOwnsTheHeader_sendsTheCookiesOfTheOriginTheServerChose() throws {
        let request = request(try storage(), managesHeader: true, cookie: "a=1")

        let derived = request.derived(method: "PATCH", url: "https://cdn.example.org/parts/1")

        #expect(derived.headers["Cookie"] == ["b=2"])
    }

    @Test
    func derived_whenTheJarHoldsNothingForTheOrigin_sendsNoCookie() throws {
        let request = request(try storage(), managesHeader: true, cookie: "a=1")

        let derived = request.derived(method: "PATCH", url: "https://elsewhere.example.net/parts/1")

        #expect(derived.headers["Cookie"] == nil)
    }

    @Test
    func derived_whenTheCallerSetTheCookie_keepsItOnTheSameOriginAndLeavesItBehindAtAnother() throws {
        let request = request(try storage(), managesHeader: false, cookie: "mine=1")

        let sameOrigin = request.derived(method: "PATCH", url: "https://upload.example.com/files/abc")
        let otherOrigin = request.derived(method: "PATCH", url: "https://cdn.example.org/parts/1")

        #expect(sameOrigin.headers["Cookie"] == ["mine=1"])
        #expect(otherOrigin.headers["Cookie"] == nil)
    }
}
