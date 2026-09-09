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
        cnonce: @autoclosure () -> String = randomHexString()
    ) -> String {
        let algorithm = challenge.algorithm

        // HA1 -- the `-sess` variant, which additionally folds in a client/server nonce pair, is
        // rejected by `DigestChallenge.init(headerValue:)` before this is ever reached.
        let ha1 = algorithm.hexDigest("\(username):\(challenge.realm):\(password)")
        let ha2 = algorithm.hexDigest("\(method):\(uri)")

        var parameters: [(name: String, value: String, quoted: Bool)] = [
            ("username", username, true),
            ("realm", challenge.realm, true),
            ("nonce", challenge.nonce, true),
            ("uri", uri, true),
        ]

        let response: String

        if challenge.hasAuthQop {
            let cnonce = cnonce()
            let nc = "00000001"

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

    /// A fresh, random client nonce -- per RFC 7616 §3.4, it must be unpredictable, since it
    /// factors into the response hash the same way the server's own nonce does.
    private static func randomHexString(byteCount: Int = 16) -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<byteCount).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        return bytes.hexEncoded
    }
}
