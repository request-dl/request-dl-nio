//
// See LICENSE for this package's licensing information.
//

#if !canImport(NIOCore)

extension LocalServer {

    /// Portable stand-in for `NIOHTTP1.HTTPResponseStatus`, used only when this target compiles
    /// without NIOCore (see `ResponseConfiguration.Status`): just enough surface (a `code`/
    /// `reasonPhrase` pair, a memberwise init for anything else, and the specific named statics
    /// currently-portable `LocalServer`-backed tests write) for those tests to keep writing
    /// `status: .found` unchanged. Add more `static let`s here as more tests get ported.
    struct HTTPStatus: Sendable, Hashable {
        let code: UInt
        let reasonPhrase: String

        init(code: UInt, reasonPhrase: String) {
            self.code = code
            self.reasonPhrase = reasonPhrase
        }

        static let ok = HTTPStatus(code: 200, reasonPhrase: "OK")
        static let found = HTTPStatus(code: 302, reasonPhrase: "Found")
        static let notModified = HTTPStatus(code: 304, reasonPhrase: "Not Modified")
        static let serviceUnavailable = HTTPStatus(code: 503, reasonPhrase: "Service Unavailable")
    }
}

#endif
