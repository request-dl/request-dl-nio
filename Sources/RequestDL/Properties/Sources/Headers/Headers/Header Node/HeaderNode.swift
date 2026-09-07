//
// See LICENSE for this package's licensing information.
//

struct HeaderNode: PropertyNode {

    // MARK: - Internal properties

    let key: String
    let value: String
    let strategy: HeaderStrategy
    let separator: String?

    /// Whether this node is RequestDL's own untouched default `User-Agent`
    /// (``UserAgentHeader/init()``), as opposed to a caller-supplied value.
    ///
    /// `false` for every header other than the default `User-Agent`. See
    /// `RequestConfiguration.hasDefaultUserAgent` for how this is folded across every `User-Agent`
    /// node in the tree.
    let isDefaultUserAgent: Bool

    var makeHeadersClosure: @Sendable (inout HTTPHeaders) -> Void {
        { self(&$0) }
    }

    // MARK: - Init

    init(
        key: String,
        value: String,
        strategy: HeaderStrategy,
        separator: String?,
        isDefaultUserAgent: Bool = false
    ) {
        self.key = key
        self.value = value
        self.strategy = strategy
        self.separator = separator
        self.isDefaultUserAgent = isDefaultUserAgent
    }

    // MARK: - Internal methods

    func make(_ make: inout Make) async throws {
        self(&make.requestConfiguration.headers)

        if key.caseInsensitiveCompare("User-Agent") == .orderedSame {
            make.requestConfiguration.markUserAgentWritten(isDefault: isDefaultUserAgent)
        }
    }

    // MARK: - Private properties

    /// Header names whose value every governing spec defines as singular -- repeating the field
    /// line, or splicing a second value into it with whatever separator happens to be in scope,
    /// either violates the field's own grammar or produces something that fails to parse as
    /// anything valid at all.
    ///
    /// `Host`: RFC 9110 §7.2 -- a server MUST 400 a request carrying more than one. `Origin`
    /// (RFC 6454/Fetch) and `Referer` (RFC 9110 §10.1.3) are each a single serialized value, not
    /// a list. `Authorization`, `Content-Type`, and `Content-Length` are each exactly one
    /// credentials/media-type/byte-count value -- `Payload`/`Authorization`/`DigestAuthentication`
    /// already write them via a direct `headers.set(...)`, bypassing `HeaderNode` entirely, but
    /// that only stops those *specific* properties from duplicating themselves. It does nothing
    /// to stop an unrelated `CustomHeader` that happens to case-insensitively collide with one of
    /// these names (e.g. `CustomHeader(name: "content-type", ...)` after a `Payload`) from
    /// appending onto it via `.adding`, or -- worse, when a separator is also in scope -- from
    /// splicing its value directly into the existing one, silently corrupting it into a single
    /// unparseable string. Enforcing this here, for every write regardless of which `Property`
    /// produced it, is the one place that closes both vectors.
    ///
    /// Deliberately excludes `User-Agent`: combining multiple ``UserAgentHeader`` instances is a
    /// documented, intentional feature (see its own doc comment), so it cannot be forced to
    /// always overwrite the way these can.
    private static let singleValuedNames: Set<String> = [
        "host", "origin", "referer", "authorization", "content-type", "content-length",
    ]

    // MARK: - Private methods

    private func callAsFunction(_ headers: inout HTTPHeaders) {
        guard !key.isEmpty else {
            return
        }

        guard !Self.singleValuedNames.contains(key.lowercased()) else {
            headers.set(name: key, value: value)
            return
        }

        switch strategy {
        case .adding:
            if let separator {
                let currentValue = (headers[key] ?? [])
                let inlineValue = (currentValue + [value]).joined(separator: separator)
                headers.set(name: key, value: inlineValue)
            } else {
                headers.add(name: key, value: value)
            }
        case .setting:
            headers.set(name: key, value: value)
        }
    }
}

// MARK: - CustomReflectable

extension HeaderNode: CustomReflectable {

    var customMirror: Mirror {
        Mirror(
            self,
            children: [
                (label: "key", value: key),
                (label: "value", value: value),
                (label: "strategy", value: strategy),
                (label: "separator", value: separator as Any),
                (label: "isDefaultUserAgent", value: isDefaultUserAgent),
            ]
        )
    }
}
