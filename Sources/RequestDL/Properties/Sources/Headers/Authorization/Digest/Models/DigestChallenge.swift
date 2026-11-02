//
// See LICENSE for this package's licensing information.
//

/// A parsed `WWW-Authenticate: Digest ...` challenge, per RFC 7616 §3.3.
struct DigestChallenge: Sendable, Hashable {

    // MARK: - Internal properties

    let realm: String
    let nonce: String
    let opaque: String?
    /// `true` when the challenge offered `qop=auth` (or the legacy, unquoted `qop=auth`).
    /// `auth-int`, which additionally hashes the request body, is treated the same as no `qop`
    /// at all: neither is supported, see ``DigestAuthentication``'s own doc comment.
    let hasAuthQop: Bool
    let algorithm: DigestAlgorithm

    // MARK: - Inits

    /// - Parameter headerValue: A `WWW-Authenticate` header's value, which may list more than one
    /// challenge (`Basic realm="a", Digest realm="b", ...`). `nil` when none of them is a `Digest`
    /// challenge, or the `Digest` one is missing `realm`/`nonce` or asks for an unsupported
    /// `algorithm`.
    init?(headerValue: String) {
        guard let parametersString = Self.digestParameters(in: headerValue) else {
            return nil
        }

        var parameters: [String: String] = [:]

        for pair in Self.splitTopLevel(Substring(parametersString), separator: ",") {
            let keyAndValue = pair.split(separator: "=", maxSplits: 1)

            guard keyAndValue.count == 2 else {
                continue
            }

            let key = keyAndValue[0].trimming(where: \.isWhitespace).lowercased()
            var value = keyAndValue[1].trimming(where: \.isWhitespace)[...]

            if value.first == "\"", value.last == "\"", value.count >= 2 {
                value = value.dropFirst().dropLast()
            }

            parameters[key] = String(value)
        }

        guard
            let realm = parameters["realm"],
            let nonce = parameters["nonce"],
            let algorithm = DigestAlgorithm(rawValue: parameters["algorithm"]),
            !algorithm.isSession
        else {
            return nil
        }

        let opaque = parameters["opaque"]

        // `realm`, `nonce`, and `opaque` are server-chosen and get echoed back, unescaped, into the
        // client's own `Authorization` header by `DigestResponse.header(for:...)`. A `"` would
        // break out of that header's quoted-parameter syntax and a CR/LF would enable header
        // injection, so reject the whole challenge rather than forward either downstream.
        guard
            Self.isSafeQuotedValue(realm),
            Self.isSafeQuotedValue(nonce),
            opaque.map(Self.isSafeQuotedValue) ?? true
        else {
            return nil
        }

        self.realm = realm
        self.nonce = nonce
        self.opaque = opaque
        self.algorithm = algorithm
        self.hasAuthQop = Self.splitTopLevel(Substring(parameters["qop"] ?? ""), separator: ",")
            .contains { $0.trimming(where: \.isWhitespace) == "auth" }
    }

    // MARK: - Internal static methods

    /// The first `Digest` challenge among the values of every `WWW-Authenticate` header of a
    /// response, a server being free to offer `Basic` first or in another header line.
    static func first(in headerValues: [String]) -> DigestChallenge? {
        for headerValue in headerValues {
            if let challenge = DigestChallenge(headerValue: headerValue) {
                return challenge
            }
        }

        return nil
    }

    // MARK: - Private static methods

    /// The parameters of the first `Digest` challenge in `headerValue`, wherever it sits in a list
    /// of challenges: the parts after it belong to it until the next scheme starts.
    private static func digestParameters(in headerValue: String) -> String? {
        var parameters: [Substring] = []
        var isInsideDigest = false
        var foundDigest = false

        for part in splitTopLevel(Substring(headerValue), separator: ",") {
            let trimmed = part.trimming(where: \.isWhitespace)

            if let scheme = scheme(startingWith: trimmed) {
                if foundDigest {
                    break
                }

                isInsideDigest = scheme.name.lowercased() == "digest"
                foundDigest = isInsideDigest

                if isInsideDigest {
                    parameters.append(scheme.parameters)
                }
            } else if isInsideDigest {
                parameters.append(trimmed[...])
            }
        }

        return foundDigest ? parameters.joined(separator: ",") : nil
    }

    /// The authentication scheme `part` opens, if it opens one: a token followed by whitespace or
    /// by nothing, where a parameter has `=` after its name.
    private static func scheme(startingWith part: String) -> (name: String, parameters: Substring)? {
        let name = part.prefix { !$0.isWhitespace && $0 != "=" }
        let rest = part[name.endIndex...].drop(while: \.isWhitespace)

        guard !name.isEmpty, !rest.hasPrefix("=") else {
            return nil
        }

        return (String(name), rest)
    }

    /// Splits `string` on every unquoted occurrence of `separator`: a plain `split(separator:)`
    /// would also split inside a quoted value that happens to contain the same character (a
    /// `nonce`/`opaque` is server-chosen, opaque data, and RFC 7616 does not forbid a comma in
    /// one).
    private static func splitTopLevel(_ string: Substring, separator: Character) -> [Substring] {
        var parts: [Substring] = []
        var insideQuotes = false
        var start = string.startIndex
        var index = string.startIndex

        while index < string.endIndex {
            let character = string[index]

            if character == "\\", insideQuotes {
                // A quoted-pair: the next character belongs to the value, even a quote.
                index = string.index(after: index)

                if index == string.endIndex {
                    break
                }
            } else if character == "\"" {
                insideQuotes.toggle()
            } else if character == separator, !insideQuotes {
                parts.append(string[start..<index])
                start = string.index(after: index)
            }

            index = string.index(after: index)
        }

        parts.append(string[start...])
        return parts
    }

    /// Whether `value` can be safely written back inside a `name="value"` header parameter:
    /// no quote to break out of it, no CR/LF to split the header into another one.
    ///
    /// Checked over `unicodeScalars`, not `Character`: `"\r\n"` collapses into a single
    /// `Character` grapheme cluster, which would otherwise slip past a scalar-by-scalar
    /// comparison written against `Character` literals `"\r"`/`"\n"`.
    private static func isSafeQuotedValue(_ value: String) -> Bool {
        !value.unicodeScalars.contains(where: { $0 == "\"" || $0 == "\r" || $0 == "\n" })
    }
}
