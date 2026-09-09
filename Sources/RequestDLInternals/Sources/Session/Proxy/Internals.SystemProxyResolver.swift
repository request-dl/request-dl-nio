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
    /// and not the other. Both executors go through this same resolver -- including proxy
    /// auto-configuration (PAC) scripts, evaluated via `Internals.PACEvaluator`/
    /// `Internals.PACProxyCache` -- so `SystemProxy()` behaves identically regardless of which
    /// executor a session resolves to.
    package enum SystemProxyResolver {

        /// The proxy the system would use to reach `url`, or `nil` for a direct connection.
        package static func proxy(forURL url: String) async -> Internals.Proxy? {
            guard let url = URL(string: url) else {
                return nil
            }

            return await resolve(url)
        }
    }
}

#if canImport(Darwin) && canImport(CFNetwork)

extension Internals.SystemProxyResolver {

    /// - Note: `CFNetworkCopyProxiesForURL` already applies the exception list, per interface
    /// settings and the enable flags, so the result is the answer for this URL specifically
    /// rather than the raw settings dictionary.
    private static func resolve(_ url: URL) async -> Internals.Proxy? {
        guard let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() else {
            return nil
        }

        let proxies =
            CFNetworkCopyProxiesForURL(url as CFURL, settings)
            .takeRetainedValue() as? [[String: Any]] ?? []

        switch firstResolution(in: proxies) {
        case .none, .direct:
            return nil

        case .proxy(let proxy):
            return proxy

        case .autoConfiguration(let scriptURL):
            return await Internals.PACProxyCache.shared.proxy(forScriptURL: scriptURL, targetURL: url)
        }
    }

    /// What one entry in a CFNetwork proxy-list dictionary resolves to -- shared between the
    /// direct `CFNetworkCopyProxiesForURL` result here and a PAC script's own evaluated result
    /// (`Internals.PACEvaluator`), since both use the identical dictionary shape.
    package enum Resolution: Sendable, Equatable {
        /// An explicit "go direct" for this URL (`kCFProxyTypeNone`).
        case direct
        /// A directly usable proxy (`kCFProxyTypeHTTP`/`kCFProxyTypeHTTPS`/`kCFProxyTypeSOCKS`).
        case proxy(Internals.Proxy)
        /// A PAC script still needs to be fetched and evaluated
        /// (`kCFProxyTypeAutoConfigurationURL`) before a proxy (or direct connection) is known.
        /// Never itself produced by evaluating a PAC script -- CFNetwork's own guarantee that a
        /// script cannot chain to another PAC file.
        case autoConfiguration(URL)
    }

    /// Walks `proxies` and returns the first entry this package recognizes -- `.direct` ends the
    /// search outright (later entries are fallbacks for a failed proxy, not alternatives), an
    /// unrecognized or unparseable entry is skipped in favor of the next one.
    package static func firstResolution(in proxies: [[String: Any]]) -> Resolution? {
        for proxy in proxies {
            guard let type = proxy[kCFProxyTypeKey as String] as? String else {
                continue
            }

            switch type {
            case kCFProxyTypeNone as CFString:
                return .direct

            case kCFProxyTypeHTTP as CFString, kCFProxyTypeHTTPS as CFString:
                if let resolved = makeProxy(proxy, connection: .http) {
                    return .proxy(resolved)
                }

            case kCFProxyTypeSOCKS as CFString:
                if let resolved = makeProxy(proxy, connection: .socks) {
                    return .proxy(resolved)
                }

            case kCFProxyTypeAutoConfigurationURL as CFString:
                if let scriptURL = proxy[kCFProxyAutoConfigurationURLKey as String] as? URL {
                    return .autoConfiguration(scriptURL)
                }

            default:
                continue
            }
        }

        return nil
    }

    /// `Internals.PACEvaluator`'s own entry point: reduces a PAC script's evaluated proxy list
    /// straight to the first usable `Internals.Proxy`, discarding `.direct`/unresolved the same
    /// way `resolve(_:)` above does for its own `nil` case.
    package static func firstUsableProxy(in proxies: [[String: Any]]) -> Internals.Proxy? {
        guard case .proxy(let proxy) = firstResolution(in: proxies) else {
            return nil
        }
        return proxy
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
    private static func resolve(_ url: URL) async -> Internals.Proxy? {
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
