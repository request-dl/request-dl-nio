//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.URL
import class Foundation.NSNumber
#endif

#if canImport(Darwin)
#if canImport(CFNetwork)
import CFNetwork
#else
import Foundation
#endif
#endif

extension Internals {

    /// Reads the proxy the operating system would use for a given URL.
    ///
    /// `AsyncHTTPClient` has no discovery of its own: its proxy is explicit configuration and
    /// nothing else. `URLSession` goes through CFNetwork, which reads the system settings, and
    /// that difference is why an interception proxy such as Proxyman or Charles captures one
    /// and not the other.
    ///
    /// - Note: Proxy auto configuration is deliberately not evaluated. See ``resolve(_:)``.
    enum SystemProxyResolver {

        /// The proxy the system would use to reach `url`, or `nil` for a direct connection.
        static func proxy(forURL url: String) -> Internals.Proxy? {
            guard let url = URL(string: url) else {
                return nil
            }

            return resolve(url)
        }
    }
}

#if canImport(Darwin) && canImport(CFNetwork)

extension Internals.SystemProxyResolver {

    /// - Note: `CFNetworkCopyProxiesForURL` already applies the exception list, per interface
    /// settings and the enable flags, so the result is the answer for this URL specifically
    /// rather than the raw settings dictionary.
    ///
    /// Auto configuration entries are skipped. Resolving a PAC script means either driving
    /// `CFNetworkExecuteProxyAutoConfigurationURL` through a run loop, or fetching the script
    /// and evaluating it, and both bring a cache and a fetch timeout along with them. Skipping
    /// them means a PAC only network falls back to a direct connection, which is the same thing
    /// that happens today.
    private static func resolve(_ url: URL) -> Internals.Proxy? {
        guard let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() else {
            return nil
        }

        let proxies =
            CFNetworkCopyProxiesForURL(url as CFURL, settings)
            .takeRetainedValue() as? [[String: Any]] ?? []

        for proxy in proxies {
            guard let type = proxy[kCFProxyTypeKey as String] as? String else {
                continue
            }

            switch type {
            case kCFProxyTypeNone as CFString:
                // An explicit "go direct" for this URL. Later entries are fallbacks for a
                // failed proxy, not alternatives, so this ends the search.
                return nil

            case kCFProxyTypeHTTP as CFString, kCFProxyTypeHTTPS as CFString:
                if let resolved = makeProxy(proxy, connection: .http) {
                    return resolved
                }

            case kCFProxyTypeSOCKS as CFString:
                if let resolved = makeProxy(proxy, connection: .socks) {
                    return resolved
                }

            default:
                continue
            }
        }

        return nil
    }

    private static func makeProxy(
        _ dictionary: [String: Any],
        connection: Internals.Proxy.ConnectionProtocol
    ) -> Internals.Proxy? {
        guard
            let host = dictionary[kCFProxyHostNameKey as String] as? String,
            let port = (dictionary[kCFProxyPortNumberKey as String] as? NSNumber)?.intValue
        else { return nil }

        return .init(
            host: host,
            port: port,
            connection: connection,
            // Rarely present. The system usually keeps the password in the keychain and hands
            // it to CFNetwork on demand, so a proxy that needs credentials generally still
            // wants an explicit `Proxy`.
            authorization: authorization(dictionary)
        )
    }

    private static func authorization(_ dictionary: [String: Any]) -> Internals.Proxy.Authorization? {
        guard
            let username = dictionary[kCFProxyUsernameKey as String] as? String,
            let password = dictionary[kCFProxyPasswordKey as String] as? String
        else { return nil }

        return .basic(username: username, password: password)
    }
}

#else

extension Internals.SystemProxyResolver {

    /// The conventional environment variables, which is what "the system proxy" means outside
    /// of Apple platforms.
    private static func resolve(_ url: URL) -> Internals.Proxy? {
        let environment = ProcessInfo.processInfo.environment

        guard let host = url.host else {
            return nil
        }

        guard !isExcluded(host, by: environment["no_proxy"] ?? environment["NO_PROXY"]) else {
            return nil
        }

        let names =
            url.scheme?.lowercased() == "https"
            ? ["https_proxy", "HTTPS_PROXY", "http_proxy", "HTTP_PROXY"]
            : ["http_proxy", "HTTP_PROXY"]

        guard
            let value = names.lazy.compactMap({ environment[$0] }).first,
            let proxy = URL(string: value),
            let proxyHost = proxy.host
        else { return nil }

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

    private static func isExcluded(_ host: String, by list: String?) -> Bool {
        guard let list, !list.isEmpty else {
            return false
        }

        let host = host.lowercased()

        return
            list
            .split(separator: ",")
            .map { $0.trimming(where: \.isWhitespace).lowercased() }
            .contains { entry in
                guard entry != "*" else {
                    return true
                }

                let bare = entry.hasPrefix(".") ? String(entry.dropFirst()) : entry
                return host == bare || host.hasSuffix(".\(bare)")
            }
    }
}

#endif
