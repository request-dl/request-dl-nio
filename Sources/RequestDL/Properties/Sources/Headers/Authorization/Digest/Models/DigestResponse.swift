//
// See LICENSE for this package's licensing information.
//

/// Computes the `response` value and assembles the full `Authorization: Digest ...` header, per
/// RFC 7616 §3.4.
enum DigestResponse {

    // MARK: - Internal static methods

    static func header(
        for challenge: DigestChallenge,
        username: String,
        password: String,
        method: String,
        uri: String,
        nc: @autoclosure () -> String = "00000001",
        cnonce: @autoclosure () -> String = randomHexString()
    ) -> String {
        let algorithm = challenge.algorithm

        // HA1: the `-sess` variant, which additionally folds in a client/server nonce pair, is
        // rejected by `DigestChallenge.init(headerValue:)` before this is ever reached.
        let ha1 = algorithm.hexDigest("\(username):\(challenge.realm):\(password)")
        let ha2 = algorithm.hexDigest("\(method):\(uri)")

        var parameters: [(name: String, value: String, quoted: Bool)] = [
            ("username", Self.escapeQuotedValue(username), true),
            ("realm", challenge.realm, true),
            ("nonce", challenge.nonce, true),
            ("uri", Self.escapeQuotedValue(uri), true),
        ]

        let response: String

        if challenge.hasAuthQop {
            let cnonce = cnonce()
            let nc = nc()

            response = algorithm.hexDigest("\(ha1):\(challenge.nonce):\(nc):\(cnonce):auth:\(ha2)")

            parameters.append(("qop", "auth", false))
            parameters.append(("nc", nc, false))
            parameters.append(("cnonce", cnonce, true))
        } else {
            response = algorithm.hexDigest("\(ha1):\(challenge.nonce):\(ha2)")
        }

        parameters.append(("response", response, true))
        parameters.append(("algorithm", algorithm.headerValue, false))

        if let opaque = challenge.opaque {
            parameters.append(("opaque", opaque, true))
        }

        let joined =
            parameters
            .map { name, value, quoted in
                quoted ? "\(name)=\"\(value)\"" : "\(name)=\(value)"
            }
            .joined(separator: ", ")

        return "Digest \(joined)"
    }

    // MARK: - Private static methods

    /// Escapes `value` for safe inclusion inside a `name="value"` header parameter: `\` and `"`
    /// are backslash-escaped per RFC 7230 §3.2.6's `quoted-pair`, and CR/LF — which `quoted-pair`
    /// has no valid escape for — are stripped outright, the same characters
    /// `DigestChallenge.isSafeQuotedValue` rejects in the server-sent fields this same header
    /// echoes back.
    ///
    /// Applied to `username` and `uri`: the two quoted parameters here that can carry
    /// caller-supplied content (`uri` is built from `Path`/`Query` components, which are commonly
    /// derived from external data such as a resource id) rather than server- or
    /// package-generated content already known to be safe. Unlike `realm`/`nonce`/`opaque`
    /// (rejecting the whole challenge is fine — the server sent something unusable), silently
    /// dropping the `Authorization` header over an escapable character in the caller's own
    /// input would be a worse failure mode than escaping it, so this repairs the value instead
    /// of refusing it. The hash inputs above still use the literal `username`/`uri`, not this
    /// escaped copy: the digest response must match what the server computes from the request as
    /// given, not from its header-safe representation.
    private static func escapeQuotedValue(_ value: String) -> String {
        var result = ""
        result.reserveCapacity(value.count)

        for scalar in value.unicodeScalars {
            switch scalar {
            case "\r", "\n":
                continue
            case "\"", "\\":
                result.unicodeScalars.append("\\")
                result.unicodeScalars.append(scalar)
            default:
                result.unicodeScalars.append(scalar)
            }
        }

        return result
    }

    /// A fresh, random client nonce. Per RFC 7616 §3.4, it must be unpredictable, since it
    /// factors into the response hash the same way the server's own nonce does.
    private static func randomHexString(byteCount: Int = 16) -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<byteCount).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        return bytes.hexEncoded
    }
}
