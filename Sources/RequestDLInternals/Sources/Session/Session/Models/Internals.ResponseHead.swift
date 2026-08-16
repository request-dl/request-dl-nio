//
// See LICENSE for this package's licensing information.
//

extension Internals {

    package struct ResponseHead: Sendable, Codable, Hashable {

        package struct Status: Sendable, Codable, Hashable {
            package let code: UInt
            package let reason: String

            package init(code: UInt, reason: String) {
                self.code = code
                self.reason = reason
            }
        }

        package struct Version: Sendable, Codable, Hashable {
            package let minor: Int
            package let major: Int

            package init(minor: Int, major: Int) {
                self.minor = minor
                self.major = major
            }
        }

        /// A single name-value header pair.
        ///
        /// `RequestDL.HTTPHeaders` is the rich, order-preserving representation `RequestDL`
        /// exposes publicly, but it lives in the `RequestDL` module, which depends on this one --
        /// so `ResponseHead`, used throughout the transport layer, carries headers as a plain
        /// `Codable` array of pairs instead. `RequestDL` converts to/from its own `HTTPHeaders`
        /// at the boundary.
        package struct HeaderField: Sendable, Codable, Hashable {
            package let name: String
            package let value: String

            package init(name: String, value: String) {
                self.name = name
                self.value = value
            }
        }

        package let url: String
        package let status: Status
        package let version: Version
        package let headers: [HeaderField]
        package let isKeepAlive: Bool

        package init(
            url: String,
            status: Status,
            version: Version,
            headers: [HeaderField],
            isKeepAlive: Bool
        ) {
            self.url = url
            self.status = status
            self.version = version
            self.headers = headers
            self.isKeepAlive = isKeepAlive
        }

        /// The values of every field named `name`, compared case insensitively per RFC 9110.
        package func headerValues(named name: String) -> [String] {
            let name = name.lowercased()

            return headers
                .filter { $0.name.lowercased() == name }
                .map(\.value)
        }
    }
}
