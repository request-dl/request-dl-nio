//
// See LICENSE for this package's licensing information.
//

#if canImport(NIOCore)
import NIOHTTP1
#endif

extension LocalServer {

    /// Portable status line, used regardless of which backend actually serves ``LocalServer``'s
    /// requests. Only the handful of codes the test suite actually configures a response with;
    /// add more here if a new test needs one.
    struct HTTPStatus: Sendable, Hashable {
        let code: Int
        let reasonPhrase: String

        static let ok = HTTPStatus(code: 200, reasonPhrase: "OK")
        static let found = HTTPStatus(code: 302, reasonPhrase: "Found")
        static let notModified = HTTPStatus(code: 304, reasonPhrase: "Not Modified")

        #if canImport(NIOCore)
        func build() -> NIOHTTP1.HTTPResponseStatus {
            .init(statusCode: code, reasonPhrase: reasonPhrase)
        }
        #endif
    }
}
