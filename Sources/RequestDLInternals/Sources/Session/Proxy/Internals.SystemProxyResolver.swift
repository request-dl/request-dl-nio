//
// See LICENSE for this package's licensing information.
//

import Logging

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.URL
import struct Foundation.URLComponents
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
    /// and not the other. Both executors go through this same resolver, including proxy
    /// auto-configuration (PAC) scripts evaluated via `Internals.PACEvaluator`/
    /// `Internals.PACProxyCache`, so `SystemProxy()` behaves identically regardless of which
    /// executor a session resolves to.
    package enum SystemProxyResolver {

        /// What a request does when the PAC script that decides its proxy cannot be asked.
        package enum PACFailurePolicy: Sendable, Hashable {

            /// What to do when there is no last answer to fall back on.
            package enum Fallback: Sendable, Hashable {
                case direct
                case fail
            }

            /// Connect directly, and say so in the log.
            case direct
            /// Fail the request with ``Internals/PACEvaluationFailure``.
            case fail
            /// Use the last answer the script gave for this URL, and say so in the log; and when it
            /// never gave one, do what `fallback` says.
            case lastKnown(orElse: Fallback)
        }

        /// How a request deals with a PAC script: what a failure does, and the two times that
        /// bound it.
        package struct PACOptions: Sendable, Hashable {

            /// 30 seconds, not a tighter bound: a PAC file is commonly hosted on a slow internal
            /// server reached over a real (if sluggish) corporate network, and this only ever costs
            /// one request's worth of latency per window thanks to the cache.
            package static let defaultEvaluationTimeout: Double = 30

            /// 10 seconds, short: a failure is usually a dropped connection or a slow server, and
            /// remembering it for minutes would send every request in that window around the proxy
            /// the script would have chosen. Not zero, because an unreachable PAC server otherwise
            /// makes every request wait out the whole evaluation timeout.
            package static let defaultFailureLifetime: Int64 = 10 * 1_000_000_000

            package var onFailure: PACFailurePolicy

            /// How long evaluating a script may take, in seconds.
            package var evaluationTimeout: Double

            /// How long a failure is remembered, in nanoseconds. Until it passes, a request asks
            /// nobody and gets the failure.
            package var failureLifetime: Int64

            package init(
                onFailure: PACFailurePolicy = .direct,
                evaluationTimeout: Double = PACOptions.defaultEvaluationTimeout,
                failureLifetime: Int64 = PACOptions.defaultFailureLifetime
            ) {
                self.onFailure = onFailure
                self.evaluationTimeout = evaluationTimeout
                self.failureLifetime = failureLifetime
            }
        }

        /// The proxy the system would use to reach `url`, or `nil` for a direct connection,
        /// including when a PAC script cannot be asked.
        package static func proxy(forURL url: String) async -> Internals.Proxy? {
            (try? await proxy(forURL: url, pac: PACOptions(), logger: nil)) ?? nil
        }

        /// The proxy the system would use to reach `url`, or `nil` for a direct connection.
        ///
        /// - Parameters:
        ///   - pac: What to do when the system's proxy is a PAC script that cannot be fetched or
        ///   run, and how long the script may take and a failure is remembered.
        ///   - logger: Where a failure that did not fail the request is reported.
        /// - Throws: ``Internals/PACEvaluationFailure`` when the policy is to fail, and
        /// `CancellationError` when the caller was cancelled while the script was being asked and
        /// going direct is not what the policy does.
        package static func proxy(
            forURL url: String,
            pac: PACOptions,
            logger: Logger?
        ) async throws -> Internals.Proxy? {
            guard let url = URL(string: url) else {
                return nil
            }

            return try await resolve(url, pac: pac, logger: logger)
        }

        /// What `policy` makes of how a PAC script came out.
        ///
        /// A script that answered is its answer under any policy. A failure goes direct and is
        /// reported, or throws, or is stood in for by the last answer the script gave. A caller
        /// that was cancelled while it waited keeps going direct, as it always did, unless the
        /// policy ends in failing, where going direct would be the one thing the policy is there
        /// to prevent.
        package static func apply(
            _ resolution: Internals.PACResolution,
            policy: PACFailurePolicy,
            scriptURL: URL,
            logger: Logger?
        ) throws -> Internals.Proxy? {
            switch resolution {
            case .answered(let proxy):
                return proxy

            case .failed(let failure, let lastKnown):
                switch policy {
                case .fail:
                    throw failure

                case .direct:
                    return wentDirect(failure, scriptURL: scriptURL, logger: logger)

                case .lastKnown(let fallback):
                    if let lastKnown {
                        Internals.Log.proxyAutoConfigurationFailedUsedLastAnswer(
                            scriptURL: scriptURL,
                            failure: failure,
                            ageNanoseconds: lastKnown.ageNanoseconds
                        )
                        .log(level: .warning, logger: logger)

                        return lastKnown.proxy
                    }

                    switch fallback {
                    case .fail:
                        throw failure

                    case .direct:
                        return wentDirect(failure, scriptURL: scriptURL, logger: logger)
                    }
                }

            case .cancelled:
                switch policy {
                case .fail, .lastKnown(orElse: .fail):
                    throw CancellationError()

                case .direct, .lastKnown(orElse: .direct):
                    return nil
                }
            }
        }

        private static func wentDirect(
            _ failure: Internals.PACEvaluationFailure,
            scriptURL: URL,
            logger: Logger?
        ) -> Internals.Proxy? {
            Internals.Log.proxyAutoConfigurationFailedWentDirect(
                scriptURL: scriptURL,
                failure: failure
            )
            .log(level: .warning, logger: logger)

            return nil
        }
    }
}

#if canImport(Darwin) && canImport(CFNetwork)

extension Internals.SystemProxyResolver {

    /// - Note: `CFNetworkCopyProxiesForURL` already applies the exception list, per interface
    /// settings and the enable flags, so the result is the answer for this URL specifically
    /// rather than the raw settings dictionary.
    private static func resolve(
        _ url: URL,
        pac: PACOptions,
        logger: Logger?
    ) async throws -> Internals.Proxy? {
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
            return try apply(
                await Internals.PACProxyCache.shared.resolution(
                    forScriptURL: scriptURL,
                    targetURL: url,
                    evaluationTimeout: pac.evaluationTimeout,
                    failureLifetime: pac.failureLifetime
                ),
                policy: pac.onFailure,
                scriptURL: scriptURL,
                logger: logger
            )
        }
    }

    /// What one entry in a CFNetwork proxy-list dictionary resolves to: shared between the
    /// direct `CFNetworkCopyProxiesForURL` result here and a PAC script's own evaluated result
    /// (`Internals.PACEvaluator`), since both use the identical dictionary shape.
    package enum Resolution: Sendable, Equatable {
        /// An explicit "go direct" for this URL (`kCFProxyTypeNone`).
        case direct
        /// A directly usable proxy (`kCFProxyTypeHTTP`/`kCFProxyTypeHTTPS`/`kCFProxyTypeSOCKS`).
        case proxy(Internals.Proxy)
        /// A PAC script still needs to be fetched and evaluated
        /// (`kCFProxyTypeAutoConfigurationURL`) before a proxy (or direct connection) is known.
        /// Never itself produced by evaluating a PAC script: CFNetwork's own guarantee that a
        /// script cannot chain to another PAC file.
        case autoConfiguration(URL)
    }

    /// Walks `proxies` and returns the first entry this package recognizes: `.direct` ends the
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
    ///
    /// - Important: Deliberately stops at env vars and never reads PAC (proxy auto-configuration)
    /// here, even though `Internals.PACEvaluator`/`Internals.PACProxyCache` already exist and are
    /// wired into the Darwin branch above. Two separate problems block porting that here:
    ///
    ///   1. **Finding whether a PAC script is configured, and its URL, has no OS-standard answer
    ///      outside Darwin.** `CFNetworkCopySystemProxySettings` folds in every source (network
    ///      profile, IT-managed config, user setting) behind one call; nothing here does.
    ///      - Windows: the readable trace is `HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\
    ///        Internet Settings\AutoConfigURL`, but WinInet actually resolves the *active*
    ///        connection from a binary `DefaultConnectionSettings` blob under `...\Internet
    ///        Settings\Connections`, so a naive registry read can disagree with what the OS would
    ///        really use. The correct source is the Win32 `WinHttpGetIEProxyConfigForCurrentUser`
    ///        API (plus `WinHttpGetProxyForUrl`/`WinHttpDetectAutoProxyConfigUrl` for WPAD, when
    ///        "automatically detect settings" rather than a fixed URL is what's configured),
    ///        which means C interop against `winhttp.h`, not a file or registry read.
    ///      - Linux has no cross-desktop standard at all. GNOME keeps it in dconf, readable via
    ///        `gsettings get org.gnome.system.proxy autoconfig-url` (only meaningful once `mode`
    ///        reads `'auto'`); KDE keeps it in `~/.config/kioslaverc` under `[Proxy Settings]` as
    ///        `Proxy Config Script`, gated on `ProxyType=2`. Neither is reachable without either
    ///        shelling out to a desktop-specific tool or linking a desktop-specific library, and a
    ///        headless/server or non-GNOME/non-KDE Linux box has nowhere to look at all.
    ///
    ///   2. **Evaluating the script once fetched needs a JavaScript engine.** CFNetwork gives
    ///      Darwin `CFNetworkExecuteProxyAutoConfigurationURL` for free; nothing here replaces it
    ///      except writing a PAC-specific JS-subset interpreter or embedding an engine (e.g.
    ///      QuickJS via C interop), a new dependency this package's Android/musl/static-SDK CI
    ///      targets would all need to keep compiling against.
    ///
    /// Both are real, separate pieces of work. `Internals.PACEvaluator`/`Internals.PACProxyCache`
    /// only cover problem 2, so porting either here still leaves problem 1 completely unsolved.
    ///
    /// For the same reasons there is no PAC script to fail here, so `pac` has nothing to decide.
    private static func resolve(
        _ url: URL,
        pac: PACOptions,
        logger: Logger?
    ) async throws -> Internals.Proxy? {
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
