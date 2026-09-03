//
// See LICENSE for this package's licensing information.
//

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
/// URL), and `-G`/`--get`. Anything else is rejected with ``CURLParsingError/Context/unsupportedFlag``
/// rather than silently ignored.
enum CURLCommandParser {

    // MARK: - Internal static methods

    static func parse(_ command: String) async throws -> RequestConfiguration {
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

                if name.caseInsensitiveCompare("Content-Type") == .orderedSame {
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

            // Ignored outright, not routed through `value(for:)`/`RequestConfiguration` at all:
            // every one of these only shapes curl's own CLI output (what it prints, and how) and
            // has zero effect on the bytes that go over the wire, so there is nothing to apply
            // here to begin with. See `CURLParsingError` and `CURLTask`'s own doc comment for why
            // this is a narrow, explicit allowlist rather than "anything unrecognized is a no-op"
            // — a flag that *does* change request/response behavior (`-L`, `--compressed`, `-k`,
            // cookie jars, ...) still has to throw, since silently ignoring one of those would
            // make the request actually performed diverge from what the pasted command does.
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

        return configuration
    }

    // MARK: - Private static methods

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

        let value = String(string[string.startIndex ..< semicolonIndex])
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

        let head = String(string[string.startIndex ..< separatorIndex])
            .trimming(where: \.isWhitespace)

        let tail = String(string[string.index(after: separatorIndex)...])
            .trimming(where: \.isWhitespace)

        return (head, tail)
    }
}
