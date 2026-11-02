//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.URL
#endif

extension Internals.SystemProxyResolver {

    /// The proxy that the conventional environment variables name for `url`, or `nil` for a direct
    /// connection.
    ///
    /// Not tied to a platform so it can be tested everywhere; only the platforms without CFNetwork
    /// call it, since Apple platforms read the system settings instead.
    ///
    /// Follows what curl does:
    /// - `https` looks only at `https_proxy`. `http_proxy` is for `http`.
    /// - An upper-case `HTTP_PROXY` is ignored when `REQUEST_METHOD` is set. A CGI server turns a
    ///   request's `Proxy:` header into that variable (httpoxy), and the request would then pick
    ///   the proxy for the server's own outgoing connections.
    /// - `no_proxy` entries are names, suffixes, `host:port`, `*`, and address ranges in CIDR
    ///   notation.
    static func proxy(forURL url: URL, environment: [String: String]) -> Internals.Proxy? {
        guard let host = url.host else {
            return nil
        }

        let scheme = url.scheme?.lowercased()

        guard
            !isExcluded(
                host: host,
                port: url.port ?? Self.defaultPort(forScheme: scheme),
                by: environment["no_proxy"] ?? environment["NO_PROXY"]
            )
        else {
            return nil
        }

        var names = scheme == "https" ? ["https_proxy", "HTTPS_PROXY"] : ["http_proxy"]

        if scheme != "https", environment["REQUEST_METHOD"] == nil {
            names.append("HTTP_PROXY")
        }

        guard
            let value = names.lazy.compactMap({ environment[$0] }).first,
            let proxy = URL(string: value),
            let proxyHost = proxy.host
        else {
            return nil
        }

        let connection: Internals.Proxy.ConnectionProtocol =
            proxy.scheme?.lowercased().hasPrefix("socks") == true ? .socks : .http

        let authorization: Internals.Proxy.Authorization?

        if let username = proxy.user, let password = proxy.password {
            authorization = .basic(username: username, password: password)
        } else {
            authorization = nil
        }

        return .init(
            host: proxyHost,
            port: proxy.port ?? (connection == .socks ? 1080 : 8080),
            connection: connection,
            authorization: authorization
        )
    }

    // MARK: - no_proxy

    private static func defaultPort(forScheme scheme: String?) -> Int? {
        switch scheme {
        case "http", "ws":
            return 80
        case "https", "wss":
            return 443
        default:
            return nil
        }
    }

    private static func isExcluded(host: String, port: Int?, by list: String?) -> Bool {
        guard let list, !list.isEmpty else {
            return false
        }

        let host = unbracketed(host.lowercased())
        let address = IPAddress(host)

        return
            list
            .split(separator: ",")
            .map { $0.trimming(where: \.isWhitespace).lowercased() }
            .contains { entry in
                !entry.isEmpty && matches(entry: entry, host: host, address: address, port: port)
            }
    }

    private static func matches(entry: String, host: String, address: IPAddress?, port: Int?) -> Bool {
        if entry == "*" {
            return true
        }

        if let slash = entry.lastIndex(of: "/") {
            guard
                let address,
                let range = IPAddress(unbracketed(String(entry[..<slash]))),
                let prefix = Int(entry[entry.index(after: slash)...])
            else {
                return false
            }

            return range.contains(address, prefixLength: prefix)
        }

        let (name, entryPort) = split(entry)

        if let entryPort, entryPort != port {
            return false
        }

        var bare = name

        if bare.hasPrefix("*.") {
            bare = String(bare.dropFirst())
        }

        if bare.hasPrefix(".") {
            bare = String(bare.dropFirst())
        }

        return host == bare || host.hasSuffix(".\(bare)")
    }

    /// `host`, `host:port` and `[v6]:port`. A bare IPv6 address has several colons and no port.
    private static func split(_ entry: String) -> (name: String, port: Int?) {
        if entry.hasPrefix("["), let close = entry.firstIndex(of: "]") {
            let name = String(entry[entry.index(after: entry.startIndex)..<close])
            let rest = entry[entry.index(after: close)...]

            return (name, rest.hasPrefix(":") ? Int(rest.dropFirst()) : nil)
        }

        guard
            entry.filter({ $0 == ":" }).count == 1,
            let colon = entry.firstIndex(of: ":"),
            let port = Int(entry[entry.index(after: colon)...])
        else {
            return (entry, nil)
        }

        return (String(entry[..<colon]), port)
    }

    private static func unbracketed(_ host: String) -> String {
        host.hasPrefix("[") && host.hasSuffix("]") ? String(host.dropFirst().dropLast()) : host
    }

    // MARK: - Addresses

    /// An IPv4 or IPv6 address as its bytes, enough to tell whether a host is inside a range.
    private struct IPAddress {

        let bytes: [UInt8]

        init?(_ string: String) {
            if let bytes = Self.parseIPv4(string) ?? Self.parseIPv6(string) {
                self.bytes = bytes
            } else {
                return nil
            }
        }

        /// Whether `other` is in the range that starts at this address and keeps the first
        /// `prefixLength` bits.
        func contains(_ other: IPAddress, prefixLength: Int) -> Bool {
            guard bytes.count == other.bytes.count, (0...(bytes.count * 8)).contains(prefixLength) else {
                return false
            }

            for index in 0..<bytes.count {
                let bits = min(8, max(0, prefixLength - index * 8))
                let mask = bits == 0 ? UInt8(0) : UInt8(truncatingIfNeeded: 0xFF << (8 - bits))

                if bytes[index] & mask != other.bytes[index] & mask {
                    return false
                }
            }

            return true
        }

        private static func parseIPv4(_ string: String) -> [UInt8]? {
            let parts = string.split(separator: ".", omittingEmptySubsequences: false)

            guard parts.count == 4 else {
                return nil
            }

            var bytes: [UInt8] = []

            for part in parts {
                guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }), let byte = UInt8(part) else {
                    return nil
                }

                bytes.append(byte)
            }

            return bytes
        }

        private static func parseIPv6(_ string: String) -> [UInt8]? {
            guard string.contains(":") else {
                return nil
            }

            // `::` stands for the zeros left out, and may appear once.
            var halves: [String] = []
            var start = string.startIndex
            var index = string.startIndex

            while index < string.endIndex {
                let next = string.index(after: index)

                if string[index] == ":", next < string.endIndex, string[next] == ":" {
                    halves.append(String(string[start..<index]))
                    start = string.index(after: next)
                    index = start
                } else {
                    index = next
                }
            }

            halves.append(String(string[start...]))

            guard halves.count <= 2 else {
                return nil
            }

            func groups(_ text: String) -> [UInt16]? {
                guard !text.isEmpty else {
                    return []
                }

                var result: [UInt16] = []

                for group in text.split(separator: ":", omittingEmptySubsequences: false) {
                    guard (1...4).contains(group.count), let value = UInt16(group, radix: 16) else {
                        return nil
                    }

                    result.append(value)
                }

                return result
            }

            guard let head = groups(halves[0]) else {
                return nil
            }

            var all = head

            if halves.count == 2 {
                guard let tail = groups(halves[1]), head.count + tail.count < 8 else {
                    return nil
                }

                all += [UInt16](repeating: 0, count: 8 - head.count - tail.count) + tail
            }

            guard all.count == 8 else {
                return nil
            }

            return all.flatMap { [UInt8($0 >> 8), UInt8($0 & 0xFF)] }
        }
    }
}
