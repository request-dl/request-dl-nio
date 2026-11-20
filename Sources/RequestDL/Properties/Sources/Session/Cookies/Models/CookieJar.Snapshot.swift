//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension CookieJar {

    /// What a jar held at a moment, to keep somewhere and give back to a jar with
    /// ``CookieJar/init(restoring:publicSuffixList:)`` or ``CookieJar/restore(_:)``.
    ///
    /// A snapshot is a `Codable` value and nothing more: encode it with the encoder you like and
    /// keep it where you like. RequestDL writes it nowhere.
    ///
    /// - Important: A snapshot is a set of credentials. Whoever reads it can act as the user until
    ///   the servers say otherwise, so keep it where you would keep a password or a refresh token,
    ///   such as the Keychain, and never in `UserDefaults`, a backup or a log. See <doc:Using-Cookies>.
    public struct Snapshot: Sendable, Hashable, Codable {

        // MARK: - Private static properties

        /// The version written, and the newest one read.
        private static let version = 1

        // MARK: - Public properties

        /// The cookies. A snapshot you build from some of them, for example without the ones of one
        /// domain, is as good as one a jar made.
        public let cookies: [Cookie]

        // MARK: - Inits

        /// Creates a snapshot of `cookies`.
        public init(cookies: [Cookie]) {
            self.cookies = cookies
        }

        // MARK: - Codable

        private enum CodingKeys: String, CodingKey {
            case version
            case cookies
        }

        /// - Throws: A `DecodingError` when the snapshot was written by a newer version of
        ///   RequestDL, which may mean something this one would read wrongly.
        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let version = try container.decode(Int.self, forKey: .version)

            guard version >= 1, version <= Self.version else {
                throw DecodingError.dataCorruptedError(
                    forKey: .version,
                    in: container,
                    debugDescription: "Unsupported cookie jar snapshot version \(version)."
                )
            }

            cookies = try container.decode([Cookie].self, forKey: .cookies)
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(Self.version, forKey: .version)
            try container.encode(cookies, forKey: .cookies)
        }
    }
}

extension CookieJar.Snapshot: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {

    /// The number of cookies, and nothing of them.
    public var description: String {
        "CookieJar.Snapshot(cookies: \(cookies.count))"
    }

    public var debugDescription: String {
        description
    }

    public var customMirror: Mirror {
        Mirror(self, children: ["cookies": cookies.count], displayStyle: .struct)
    }
}
