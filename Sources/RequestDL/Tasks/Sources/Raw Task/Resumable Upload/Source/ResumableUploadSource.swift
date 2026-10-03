//
// See LICENSE for this package's licensing information.
//

/// Why a body could not be made readable from any offset.
enum ResumableUploadBodyError: Error, Equatable {

    /// What the compressor produced did not all end up in the buffer meant to hold it, so
    /// uploading from it would send a shorter body than the length that is declared.
    case couldNotStoreBody(expected: Int, stored: Int)
}

/// A request body that can be read again from any offset, which is what resuming an upload needs:
/// the server says how many bytes it has, and what is sent next is the body without them.
///
/// Every body already is, except one that is compressed as it is sent: its bytes only exist once
/// it is pulled, and pulling it again from the start would only be known to produce the same bytes
/// by trusting the compressor. Such a body is produced **once**, up front, and the result is what
/// is sliced, so a length is known (a protocol such as tus declares it before the first byte) and
/// the offset the server holds means the same bytes for every attempt.
struct ResumableUploadSource: Sendable {

    // MARK: - Internal static properties

    /// How much of a compressed body is kept in memory before it goes to a temporary file.
    static let defaultMemoryLimit = 8 * 1_024 * 1_024

    // MARK: - Internal properties

    /// How many bytes the whole body has.
    let length: Int64

    /// Whether the bytes live in a file rather than in memory.
    var isBackedByFile: Bool {
        body.isBackedByFile
    }

    // MARK: - Private properties

    private let body: RequestBody

    // MARK: - Inits

    /// - Parameters:
    ///   - body: The body of the request, after any compression was applied to it.
    ///   - memoryLimit: See ``RequestBody/materialized(memoryLimit:)``.
    init(_ body: RequestBody, memoryLimit: Int = Self.defaultMemoryLimit) async throws {
        let materialized = try await body.materialized(memoryLimit: memoryLimit)

        self.body = materialized
        self.length = Int64(materialized.totalSize)
    }

    // MARK: - Internal methods

    /// What is left of the body from `offset`: the bytes to send when the server already has the
    /// first `offset` of them. An `offset` at or past the end is an empty body.
    ///
    /// - Precondition: `offset` is not negative.
    func remaining(from offset: Int64) -> RequestBody {
        precondition(offset >= .zero, "Cannot resume from \(offset)")

        let count = Int(clamping: Swift.min(offset, length))

        guard let remaining = body.dropping(first: count) else {
            preconditionFailure("A materialized body is never compressing")
        }

        return remaining
    }
}
