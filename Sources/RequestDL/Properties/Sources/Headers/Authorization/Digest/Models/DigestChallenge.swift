//
// See LICENSE for this package's licensing information.
//

/// A parsed `WWW-Authenticate: Digest ...` challenge, per RFC 7616 §3.3.
struct DigestChallenge: Sendable, Hashable {

    // MARK: - Internal properties

    let realm: String
    let nonce: String
    let opaque: String?
    /// `true` when the challenge offered `qop=auth` (or the legacy, unquoted `qop=auth`) --
    /// `auth-int`, which additionally hashes the request body, is treated the same as no `qop`
    /// at all: neither is supported, see ``DigestAuthentication``'s own doc comment.
    let hasAuthQop: Bool
    let algorithm: DigestAlgorithm

    // MARK: - Inits

    /// - Parameter headerValue: A `WWW-Authenticate` header's value. `nil` when it isn't a
    /// `Digest` challenge, is missing `realm`/`nonce`, or asks for an unsupported `algorithm`.
    init?(headerValue: String) {
        let trimmed = headerValue.trimming(where: \.isWhitespace)

        guard trimmed.lowercased().hasPrefix("digest") else {
            return nil
        }

        let parametersString = trimmed.dropFirst("digest".count)
        var parameters: [String: String] = [:]

        for pair in Self.splitTopLevel(parametersString, separator: ",") {
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

        self.realm = realm
        self.nonce = nonce
        self.opaque = parameters["opaque"]
        self.algorithm = algorithm
        self.hasAuthQop = Self.splitTopLevel(Substring(parameters["qop"] ?? ""), separator: ",")
            .contains { $0.trimming(where: \.isWhitespace) == "auth" }
    }

    // MARK: - Private static methods

    /// Splits `string` on every unquoted occurrence of `separator` -- a plain `split(separator:)`
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

            if character == "\"" {
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
}
