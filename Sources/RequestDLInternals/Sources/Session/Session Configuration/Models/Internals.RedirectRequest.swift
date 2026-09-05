//
// See LICENSE for this package's licensing information.
//

import NIOHTTP1

extension Internals {

    /// Internals-layer counterpart to `RequestDL.RedirectRequest` -- see it for the meaning of
    /// each property. Kept apart because `RequestDL.HTTPHeaders` lives one layer up and cannot be
    /// referenced from here.
    package struct RedirectRequest: Sendable {

        package var url: String
        package var method: String
        package var headers: NIOHTTP1.HTTPHeaders
        package let hasBody: Bool

        package init(
            url: String,
            method: String,
            headers: NIOHTTP1.HTTPHeaders,
            hasBody: Bool
        ) {
            self.url = url
            self.method = method
            self.headers = headers
            self.hasBody = hasBody
        }
    }
}
