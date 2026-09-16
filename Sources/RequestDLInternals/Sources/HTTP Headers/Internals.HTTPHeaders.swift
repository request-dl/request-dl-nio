//
// See LICENSE for this package's licensing information.
//

#if canImport(NIOCore)
import NIOHTTP1
#endif

extension Internals {

    /// Portable, NIO-free header storage: ordered name/value pairs (duplicates and all), no
    /// case-insensitive lookup or merging, because nothing on this side of the boundary needs
    /// it. The currency `Internals.Proxy.connectHeaders` and `Internals.RedirectRequest.headers`
    /// carry (both reachable from either executor), converting to `NIOHTTP1.HTTPHeaders` only
    /// where the `.nio` executor's own APIs actually require one.
    package struct HTTPHeaders: Sendable {

        // MARK: - Internal properties

        package private(set) var pairs: [(name: String, value: String)]

        package var isEmpty: Bool {
            pairs.isEmpty
        }

        // MARK: - Inits

        package init() {
            pairs = []
        }

        package init<S: Sequence>(_ headers: S) where S.Element == (String, String) {
            pairs = headers.map { (name: $0.0, value: $0.1) }
        }

        // MARK: - Internal methods

        package mutating func add(name: String, value: String) {
            pairs.append((name: name, value: value))
        }

        /// The first value stored under `name`, compared case insensitively per RFC 9110 (same
        /// contract as `NIOHTTP1.HTTPHeaders.first(name:)`/`RequestDL.HTTPHeaders.first(name:)`).
        package func first(name: String) -> String? {
            let name = name.lowercased()
            return pairs.first { $0.name.lowercased() == name }?.value
        }

        /// Whether any value is stored under `name`, compared case insensitively.
        package func contains(name: String) -> Bool {
            first(name: name) != nil
        }
    }
}

// MARK: - Sequence

extension Internals.HTTPHeaders: Sequence {

    package func makeIterator() -> Array<(name: String, value: String)>.Iterator {
        pairs.makeIterator()
    }
}

// MARK: - ExpressibleByDictionaryLiteral

extension Internals.HTTPHeaders: ExpressibleByDictionaryLiteral {

    package init(dictionaryLiteral elements: (String, String)...) {
        self.init(elements)
    }
}

// MARK: - NIOHTTP1 bridging

#if canImport(NIOCore)
extension Internals.HTTPHeaders {

    package init(_ headers: NIOHTTP1.HTTPHeaders) {
        // `NIOHTTP1.HTTPHeaders.Element` already is `(name: String, value: String)`, so this
        // is the one copy the conversion needs — going through the generic `init<S: Sequence>`
        // instead would iterate a second time over an intermediate `Array(headers)`.
        pairs = Array(headers)
    }

    package func build() -> NIOHTTP1.HTTPHeaders {
        // `pairs` directly, not `Array(self)`: `self` is a thin `Sequence` wrapper over
        // `pairs`, so going through it re-copies what's already a plain array.
        .init(pairs)
    }
}
#endif
