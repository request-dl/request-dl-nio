/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
A structure representing the HTTP response header.

Use ResponseHead to represent the HTTP response header in your app.
*/
public struct ResponseHead: Equatable {

    /// The URL of the response.
    public let url: URL?

    /// The HTTP status of the response.
    public let status: Status

    /// The HTTP headers of the response.
    public let headers: HTTPHeaders

    /**
     Initializes a new instance of `ResponseHead` with the given parameters.

     - Parameters:
        - url: The URL of the response.
        - status: The HTTP status of the response.
        - headers: The HTTP headers of the response.
     */
    public init(
        url: URL?,
        status: Status,
        headers: HTTPHeaders
    ) {
        self.url = url
        self.status = status
        self.headers = headers
    }

    init(_ response: URLResponse) {
        guard let response = response as? HTTPURLResponse else {
            fatalError()
        }

        self.init(
            url: response.url,
            status: .init(
                code: UInt(response.statusCode),
                reason: ""
            ),
            headers: .init(Dictionary(
                response
                    .allHeaderFields
                    .map {
                        ("\($0)", "\($1)")
                    },
                uniquingKeysWith: { key, _ in key }
            ))
        )
    }
}

extension ResponseHead {

    /// A structure representing the HTTP status of a response.
    public struct Status: Equatable {

        /// The HTTP status code.
        public let code: UInt

        /// The reason phrase of the HTTP status.
        public let reason: String

        /**
         Initializes a new instance of `Status` with the given parameters.

         - Parameters:
            - code: The HTTP status code.
            - reason: The reason phrase of the HTTP status.
         */
        public init(
            code: UInt,
            reason: String
        ) {
            self.code = code
            self.reason = reason
        }
    }
}
