//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

/// Where a download stopped, and what it has to still be, to be continued later, including from a
/// new launch of the application.
///
/// A point is what is needed to ask a server for "the rest" of a resource safely: how many bytes
/// of it you already have (``offset``), and the validator (`ETag` or `Last-Modified`) of the
/// representation they came from, so that a resource that changed in the meantime is never spliced
/// onto the bytes of its old version. It is `Codable`, to be kept next to the partial file.
///
/// ```swift
/// // While downloading: keep what is needed to continue.
/// let result = try await DownloadTask { ... }.result()
/// let point = DownloadResumptionPoint(head: result.head, offset: 0)   // `nil` if not resumable
///
/// // Later, even after a relaunch: ask for the rest, from as many bytes as the partial file has.
/// let rest = try await DownloadTask { ... }
///     .continuingDownload(from: point.at(offset: bytesAlreadyOnDisk))
///     .result()
/// ```
///
/// The bytes themselves are yours: the library doesn't store a partial download, so `offset` is
/// simply the size of what you kept, which is also the only number that can't be wrong about what
/// was actually persisted.
public struct DownloadResumptionPoint: Sendable, Hashable, Codable {

    // MARK: - Public properties

    /// How many bytes of the resource come before the rest: the size of the partial download.
    public let offset: Int64

    /// How long the whole resource is, when the response the point was taken from said so.
    public let completeLength: Int64?

    /// Whether there is nothing left to download: ``offset`` is at, or past, the end of the resource.
    /// `false` when the length isn't known.
    public var isComplete: Bool {
        completeLength.map { offset >= $0 } ?? false
    }

    // MARK: - Internal properties

    let plan: Internals.RangeResumptionPlan

    // MARK: - Inits

    /// A point after `offset` bytes of the resource `head` is the response of.
    ///
    /// - Parameters:
    ///   - head: The head of the original `200` response of a `GET`.
    ///   - offset: How many bytes of its body are kept. Zero for a point taken before any are.
    /// - Returns: `nil` when that download can't be continued safely: the response is not a `200`,
    /// it has no strong validator (a strong `ETag`, or, without any `ETag`, a strong
    /// `Last-Modified`), or it carries a content coding, whose offsets don't mean what they would
    /// on the wire. Also when `offset` is negative.
    public init?(head: ResponseHead, offset: Int64) {
        guard
            offset >= .zero,
            let plan = Internals.RangeResumptionPlan(
                method: "GET",
                requestHeaderNames: [],
                response: Internals.ResponseHead(head)
            )
        else {
            return nil
        }

        self.init(plan: plan, offset: offset)
    }

    init(plan: Internals.RangeResumptionPlan, offset: Int64) {
        self.plan = plan
        self.offset = offset
        self.completeLength = plan.completeLength
    }

    // MARK: - Public methods

    /// The same point, after `offset` bytes instead.
    ///
    /// What is persisted once is the validator; how many bytes are on disk is only known when it
    /// is time to continue.
    public func at(offset: Int64) -> DownloadResumptionPoint {
        DownloadResumptionPoint(plan: plan, offset: max(offset, .zero))
    }

    // MARK: - Codable

    /// A format of its own, versioned, rather than whatever the types behind it happen to encode:
    /// a point is kept across launches, and across updates of the application, so what was written
    /// by one version has to be read by the next.
    private enum CodingKeys: String, CodingKey {
        case version
        case offset
        case completeLength
        case validator
    }

    private enum ValidatorKind: String, Codable {
        case entityTag
        case lastModified
    }

    private struct ValidatorCoding: Codable {
        let kind: ValidatorKind
        let value: String
    }

    private static let currentVersion = 1

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .version)

        guard version == Self.currentVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .version,
                in: container,
                debugDescription: "Unsupported download resumption point version \(version)"
            )
        }

        let offset = try container.decode(Int64.self, forKey: .offset)

        guard offset >= .zero else {
            throw DecodingError.dataCorruptedError(
                forKey: .offset,
                in: container,
                debugDescription: "A download resumption point can't have a negative offset"
            )
        }

        let validator = try container.decode(ValidatorCoding.self, forKey: .validator)
        let completeLength = try container.decodeIfPresent(Int64.self, forKey: .completeLength)

        self.init(
            plan: Internals.RangeResumptionPlan(
                validator: {
                    switch validator.kind {
                    case .entityTag:
                        return .entityTag(validator.value)
                    case .lastModified:
                        return .lastModified(validator.value)
                    }
                }(),
                completeLength: completeLength
            ),
            offset: offset
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentVersion, forKey: .version)
        try container.encode(offset, forKey: .offset)
        try container.encodeIfPresent(completeLength, forKey: .completeLength)

        switch plan.validator {
        case .entityTag(let value):
            try container.encode(ValidatorCoding(kind: .entityTag, value: value), forKey: .validator)
        case .lastModified(let value):
            try container.encode(ValidatorCoding(kind: .lastModified, value: value), forKey: .validator)
        }
    }
}

// MARK: - Internal conversion

extension Internals.ResponseHead {

    /// The executors' view of a response head the application has, to run what only reads one
    /// (`RangeResumptionPlan`) on it.
    init(_ head: ResponseHead) {
        self.init(
            url: head.url?.absoluteString ?? "",
            status: .init(code: head.status.code, reason: head.status.reason),
            version: .init(minor: head.version.minor, major: head.version.major),
            headers: head.headers.map { .init(name: $0.name, value: $0.value) },
            isKeepAlive: head.isKeepAlive
        )
    }
}
