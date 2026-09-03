//
// See LICENSE for this package's licensing information.
//

import NIOSSL
import RequestDLInternals

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import struct Foundation.URL
#endif

/// Parses a curl command line into a ``RequestConfiguration``.
///
/// Builds the configuration directly rather than composing a `@PropertyBuilder` tree — there is
/// no per-flag `Property` to declare, since the flags are only known at runtime. Scoped to a
/// documented subset of curl's flags: `-X`/`--request`, `-H`/`--header`, `-d`/`--data`/
/// `--data-raw`/`--data-binary`, `-F`/`--form`, `-u`/`--user`, `--url` (plus a bare trailing
/// URL), `-G`/`--get`, `-L`/`--location` (with `--max-redirs`), `-k`/`--insecure`, `-x`/`--proxy`,
/// `--resolve`, `--compressed`, `--cacert`, and `--cert`/`-E`/`--key`. Anything else is rejected
/// with ``CURLParsingError/Context/unsupportedFlag`` rather than silently ignored.
enum CURLCommandParser {

    // MARK: - Internal types

    /// A parsed command: the ``RequestConfiguration`` itself, plus — for the handful of flags
    /// that are session-level rather than request-level (`-L`, `-k`, `-x`, `--resolve`,
    /// `--compressed`, `--cacert`, `--cert`, `--key`) — an edit to apply to
    /// `Make.sessionConfiguration`. `RequestConfiguration` has no field for any of those; they
    /// live on `Internals.Session.Configuration` instead, which is why this can't just be one
    /// richer `RequestConfiguration`.
    struct Command {
        let requestConfiguration: RequestConfiguration
        let sessionConfigurationEdit: (@Sendable (inout Internals.Session.Configuration) -> Void)?
    }

    // MARK: - Internal static methods

    /// Convenience for callers that only need the request itself — every existing caller before
    /// the session-level flags below were added.
    static func parse(_ command: String) async throws -> RequestConfiguration {
        try await parseCommand(command).requestConfiguration
    }

    static func parseCommand(_ command: String) async throws -> Command {
        var tokens = try CURLTokenizer.tokenize(command)

        if tokens.first == "curl" {
            tokens.removeFirst()
        }

        var configuration = RequestConfiguration()
        var explicitMethod: String?
        var dataFragments: [String] = []
        var formItems: [FormItem] = []
        var usesGet = false
        var url: String?
        var hasExplicitContentType = false

        var followsRedirects = false
        var maxRedirects: Int?
        var isInsecure = false
        var proxy: Internals.Proxy?
        var dnsOverrides: [String: String] = [:]
        var isCompressed = false
        var caCertPath: String?
        var certPath: String?
        var keyPath: String?

        var index = tokens.startIndex

        func value(for flag: String) throws -> String {
            index += 1

            guard index < tokens.endIndex else {
                throw CURLParsingError(.malformedArgument, token: flag)
            }

            return tokens[index]
        }

        while index < tokens.endIndex {
            let token = tokens[index]

            switch token {
            case "-X", "--request":
                explicitMethod = try value(for: token)

            case "-H", "--header":
                let (name, headerValue) = try splitOnce(try value(for: token), separator: ":")
                configuration.headers.add(name: name, value: headerValue)

                // `.lowercased()`, not Foundation's `caseInsensitiveCompare(_:)` -- unavailable
                // under `FoundationEssentials`/Linux.
                if name.lowercased() == "content-type" {
                    hasExplicitContentType = true
                }

            case "-d", "--data", "--data-raw", "--data-binary":
                dataFragments.append(try value(for: token))

            case "-F", "--form":
                formItems.append(try makeFormItem(try value(for: token)))

            case "-u", "--user":
                let (username, password) = try splitOnce(try value(for: token), separator: ":")
                let credentialToken = Data("\(username):\(password)".utf8).base64EncodedString()
                configuration.headers.set(name: "Authorization", value: "Basic \(credentialToken)")

            case "--url":
                let urlValue = try value(for: token)

                // Same rule as a second bare trailing URL below: only one URL total, from
                // whichever form names it, not "last one wins" for `--url` but "reject" for a
                // bare argument.
                guard url == nil else {
                    throw CURLParsingError(.unsupportedFlag, token: urlValue)
                }

                url = urlValue

            case "-G", "--get":
                usesGet = true

            case "-L", "--location":
                followsRedirects = true

            case "--max-redirs":
                let rawValue = try value(for: token)

                guard let count = Int(rawValue) else {
                    throw CURLParsingError(.malformedArgument, token: rawValue)
                }

                maxRedirects = count

            case "-k", "--insecure":
                isInsecure = true

            case "-x", "--proxy":
                proxy = try makeProxy(try value(for: token))

            case "--resolve":
                let (host, address) = try makeDNSOverride(try value(for: token))
                dnsOverrides[host] = address

            case "--compressed":
                isCompressed = true

            case "--cacert":
                caCertPath = try value(for: token)

            case "--cert", "-E":
                certPath = try value(for: token)

            case "--key":
                keyPath = try value(for: token)

            // Ignored outright, not routed through `value(for:)`/`RequestConfiguration` at all:
            // every one of these only shapes curl's own CLI output (what it prints, and how) and
            // has zero effect on the bytes that go over the wire, so there is nothing to apply
            // here to begin with. See `CURLParsingError` and `CURLTask`'s own doc comment for why
            // this is a narrow, explicit allowlist rather than "anything unrecognized is a no-op"
            // — a flag that *does* change request/response behavior still has to throw, since
            // silently ignoring one of those would make the request actually performed diverge
            // from what the pasted command does.
            case "-s", "--silent", "-S", "--show-error", "-v", "--verbose", "-i", "--include", "-#", "--progress-bar":
                break

            // Same as above, but these also take an argument that has to be consumed so it isn't
            // mistaken for the URL.
            case "-o", "--output", "-w", "--write-out":
                _ = try value(for: token)

            default:
                guard !token.hasPrefix("-") else {
                    throw CURLParsingError(.unsupportedFlag, token: token)
                }

                guard url == nil else {
                    throw CURLParsingError(.unsupportedFlag, token: token)
                }

                url = token
            }

            index += 1
        }

        guard let url else {
            throw CURLParsingError(.missingURL)
        }

        try await apply(
            url: url,
            explicitMethod: explicitMethod,
            dataFragments: dataFragments,
            formItems: formItems,
            usesGet: usesGet,
            hasExplicitContentType: hasExplicitContentType,
            to: &configuration
        )

        return Command(
            requestConfiguration: configuration,
            sessionConfigurationEdit: makeSessionConfigurationEdit(
                followsRedirects: followsRedirects,
                maxRedirects: maxRedirects,
                isInsecure: isInsecure,
                proxy: proxy,
                dnsOverrides: dnsOverrides,
                isCompressed: isCompressed,
                caCertPath: caCertPath,
                certPath: certPath,
                keyPath: keyPath
            )
        )
    }

    // MARK: - Private static methods

    /// `nil` when none of the session-level flags were given at all — so a command using only
    /// the documented request-level subset doesn't touch `Make.sessionConfiguration` in any way,
    /// same as before these flags existed.
    ///
    /// - Important: When non-`nil`, this *always* sets `redirectConfiguration` and
    /// `decompression` explicitly, to curl's own real defaults (no redirects, no decompression)
    /// rather than leaving them `nil`/whatever they already were. Leaving either alone would mean
    /// "no `-L` in this command" silently inherited this package's own default instead of curl's
    /// — which for redirects is the *opposite* of curl's default (see `CURLTask`'s doc comment).
    /// A command with none of these session-level flags skips this distinction entirely (returns
    /// `nil` above) precisely so it doesn't newly start disabling redirects for every existing
    /// command that never asked for any of this.
    private static func makeSessionConfigurationEdit(
        followsRedirects: Bool,
        maxRedirects: Int?,
        isInsecure: Bool,
        proxy: Internals.Proxy?,
        dnsOverrides: [String: String],
        isCompressed: Bool,
        caCertPath: String?,
        certPath: String?,
        keyPath: String?
    ) -> (@Sendable (inout Internals.Session.Configuration) -> Void)? {
        guard
            followsRedirects || isInsecure || proxy != nil || !dnsOverrides.isEmpty || isCompressed
                || caCertPath != nil || certPath != nil || keyPath != nil
        else {
            return nil
        }

        return { sessionConfiguration in
            sessionConfiguration.redirectConfiguration =
                followsRedirects
                ? .follow(max: maxRedirects ?? 50, allowCycles: false)
                : .disallow

            sessionConfiguration.decompression = isCompressed ? .enabled(.none) : .disabled

            if isInsecure || caCertPath != nil || certPath != nil || keyPath != nil {
                var secureConnection = sessionConfiguration.secureConnection ?? .init()

                if isInsecure {
                    // `certificateVerification` is `NIOSSL.CertificateVerification?`, and
                    // `CertificateVerification` itself has a case named `none` -- plain `.none`
                    // here resolves to `Optional<CertificateVerification>.none` (nil), not
                    // `CertificateVerification.none`, which leaves verification at its default
                    // (`.fullVerification`) instead of disabling it. `.some(.none)`
                    // disambiguates.
                    secureConnection.certificateVerification = .some(.none)
                }

                if let caCertPath {
                    secureConnection.trustRoots = .file(caCertPath)
                }

                if let certPath {
                    secureConnection.certificateChain = .file(certPath)
                }

                if let keyPath {
                    secureConnection.privateKey = .privateKey(Internals.PrivateKey(keyPath, format: .pem))
                }

                sessionConfiguration.secureConnection = secureConnection
            }

            if let proxy {
                sessionConfiguration.proxy = proxy
            }

            if !dnsOverrides.isEmpty {
                sessionConfiguration.dnsOverride.merge(dnsOverrides) { _, new in new }
            }
        }
    }

    /// Parses `[scheme://][user[:password]@]host[:port]` (curl's `-x`/`--proxy` argument) into
    /// an `Internals.Proxy`. `socks`/`socks4`/`socks4a`/`socks5`/`socks5h` schemes all map to
    /// `.socks` — `Internals.Proxy.ConnectionProtocol` doesn't distinguish SOCKS versions.
    /// Defaults to `.http` when no scheme is given, and to port 1080 when no port is given,
    /// matching curl's own defaults.
    private static func makeProxy(_ value: String) throws -> Internals.Proxy {
        var remainder = Substring(value)
        var connectionProtocol: Internals.Proxy.ConnectionProtocol = .http

        // Neither `range(of:)` (Foundation, unavailable under `FoundationEssentials`/Linux) nor
        // `firstRange(of:)` (stdlib, but gated to macOS 13/iOS 16 -- newer than this package's
        // macOS 12/iOS 15 minimum; see `URLOverrideEndpoint.init?(baseURL:)` for the same
        // constraint). A scheme, when present, is always at the very start, so the first `:`
        // followed by `//` is unambiguous -- an earlier `:` inside `user:pass@host:port` (no
        // scheme) is never followed by `//`, so `hasPrefix("//")` alone tells the two apart.
        if let colonIndex = remainder.firstIndex(of: ":"),
            remainder[remainder.index(after: colonIndex)...].hasPrefix("//")
        {
            connectionProtocol =
                remainder[remainder.startIndex..<colonIndex]
                    .lowercased()
                    .hasPrefix("socks") ? .socks : .http

            remainder = remainder[remainder.index(colonIndex, offsetBy: 3)...]
        }

        var authorization: Internals.Proxy.Authorization?

        if let atIndex = remainder.lastIndex(of: "@") {
            let credentials = remainder[remainder.startIndex..<atIndex]
            remainder = remainder[remainder.index(after: atIndex)...]

            if let colonIndex = credentials.firstIndex(of: ":") {
                authorization = .basic(
                    username: String(credentials[credentials.startIndex..<colonIndex]),
                    password: String(credentials[credentials.index(after: colonIndex)...])
                )
            } else {
                authorization = .basic(username: String(credentials), password: "")
            }
        }

        guard !remainder.isEmpty else {
            throw CURLParsingError(.malformedArgument, token: value)
        }

        guard
            let colonIndex = remainder.lastIndex(of: ":"),
            let port = Int(remainder[remainder.index(after: colonIndex)...])
        else {
            return Internals.Proxy(
                host: String(remainder),
                port: 1080,
                connection: connectionProtocol,
                authorization: authorization
            )
        }

        return Internals.Proxy(
            host: String(remainder[remainder.startIndex..<colonIndex]),
            port: port,
            connection: connectionProtocol,
            authorization: authorization
        )
    }

    /// Parses curl's `--resolve HOST:PORT:ADDRESS` into `(host, address)` — the port is read
    /// (and validated) but then dropped: `Internals.Session.Configuration.dnsOverride` is a
    /// plain `[hostname: address]` dictionary with no port dimension to carry it in, so a
    /// `--resolve` override applies to every port on that host, not only the one named.
    private static func makeDNSOverride(_ value: String) throws -> (host: String, address: String) {
        let components = value.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)

        guard
            components.count == 3,
            !components[0].isEmpty,
            Int(components[1]) != nil,
            !components[2].isEmpty
        else {
            throw CURLParsingError(.malformedArgument, token: value)
        }

        return (String(components[0]), String(components[2]))
    }

    private static func apply(
        url: String,
        explicitMethod: String?,
        dataFragments: [String],
        formItems: [FormItem],
        usesGet: Bool,
        hasExplicitContentType: Bool,
        to configuration: inout RequestConfiguration
    ) async throws {
        configuration.baseURL = url
        configuration.method = explicitMethod

        if !formItems.isEmpty {
            configuration.method = explicitMethod ?? "POST"

            var outputs: [FormItem.Output] = []
            outputs.reserveCapacity(formItems.count)

            for item in formItems {
                outputs.append(try await item())
            }

            let builder = FormGroupBuilder(outputs)

            configuration.headers.set(
                name: "Content-Type",
                value: "multipart/form-data; boundary=\"\(builder.boundary)\""
            )

            let body = RequestBody(buffers: await builder())

            configuration.headers.set(name: "Content-Length", value: String(body.totalSize))
            configuration.body = body
            return
        }

        guard !dataFragments.isEmpty else {
            return
        }

        let joinedData = dataFragments.joined(separator: "&")

        if usesGet {
            let separator = url.contains("?") ? "&" : "?"
            configuration.baseURL = url + separator + joinedData
            return
        }

        configuration.method = explicitMethod ?? "POST"

        if !hasExplicitContentType {
            configuration.headers.set(name: "Content-Type", value: String(ContentType.formURLEncoded))
        }

        let buffer = await Internals.DataBuffer(
            try Charset.utf8.encode(joinedData)
        )

        let body = RequestBody(buffers: [buffer])

        configuration.headers.set(name: "Content-Length", value: String(body.totalSize))
        configuration.body = body
    }

    /// Parses one `-F`/`--form` field: `name=value`, or `name=@path;type=mime` for a file.
    private static func makeFormItem(_ field: String) throws -> FormItem {
        let (name, rawValue) = try splitOnce(field, separator: "=", context: field)

        guard rawValue.hasPrefix("@") else {
            let (verbatim, contentType) = splittingParameter(rawValue, prefix: "type=")

            return FormItem(
                name: name,
                filename: nil,
                additionalHeaders: nil,
                charset: RequestEnvironmentValues().charset,
                urlEncoder: RequestEnvironmentValues().urlEncoder,
                factory: StringPayloadFactory(
                    verbatim: verbatim,
                    contentType: contentType.map { ContentType($0) } ?? .text
                )
            )
        }

        let (filePath, contentType) = splittingParameter(String(rawValue.dropFirst()), prefix: "type=")
        let fileURL = URL(fileURLWithPath: filePath)

        return FormItem(
            name: name,
            filename: fileURL.lastPathComponent,
            additionalHeaders: nil,
            charset: RequestEnvironmentValues().charset,
            urlEncoder: RequestEnvironmentValues().urlEncoder,
            factory: FilePayloadFactory(
                url: fileURL,
                contentType: contentType.map { ContentType($0) } ?? .octetStream
            )
        )
    }

    /// Splits `"value;prefix<rest>"` into `("value", "<rest>")`, or `(value, nil)` when there is
    /// no `;`-separated parameter with that prefix.
    private static func splittingParameter(
        _ string: String,
        prefix: String
    ) -> (value: String, parameter: String?) {
        guard let semicolonIndex = string.firstIndex(of: ";") else {
            return (string, nil)
        }

        let value = String(string[string.startIndex..<semicolonIndex])
        let parameter = string[string.index(after: semicolonIndex)...]

        guard parameter.hasPrefix(prefix) else {
            return (value, nil)
        }

        return (value, String(parameter.dropFirst(prefix.count)))
    }

    private static func splitOnce(
        _ string: String,
        separator: Character,
        context: String? = nil
    ) throws -> (String, String) {
        guard let separatorIndex = string.firstIndex(of: separator) else {
            throw CURLParsingError(.malformedArgument, token: context ?? string)
        }

        let head = String(string[string.startIndex..<separatorIndex])
            .trimming(where: \.isWhitespace)

        let tail = String(string[string.index(after: separatorIndex)...])
            .trimming(where: \.isWhitespace)

        return (head, tail)
    }
}
