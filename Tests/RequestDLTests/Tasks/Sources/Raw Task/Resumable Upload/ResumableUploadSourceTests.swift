//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL
@testable import RequestDLInternals

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

struct ResumableUploadSourceTests {

    // MARK: - Uncompressed bodies

    @Test
    func remaining_whenFromZero_isTheWholeBody() async throws {
        // Given
        let payload = Self.bytes(count: 1_000)
        let source = try await ResumableUploadSource(Self.body(of: [payload]))

        // When
        let remaining = try await source.remaining(from: 0).data()

        // Then
        #expect(source.length == 1_000)
        #expect(remaining == payload)
    }

    @Test(arguments: [0, 1, 3, 4, 5, 9, 10, 11, 12])
    func remaining_whenBodyHasSeveralBuffers_startsExactlyAtTheOffset(_ offset: Int) async throws {
        // Given: buffers of 4, 0, 5 and 3 bytes, so offsets fall inside, between and past them.
        let parts = [Self.bytes(count: 4), Data(), Self.bytes(count: 5, seed: 7), Self.bytes(count: 3, seed: 9)]
        let whole = parts.reduce(Data(), +)
        let source = try await ResumableUploadSource(Self.body(of: parts))

        // When
        let remaining = try await source.remaining(from: Int64(offset)).data()

        // Then
        #expect(source.length == Int64(whole.count))
        #expect(remaining == whole.dropFirst(offset))
    }

    @Test
    func remaining_whenPastTheEnd_isEmpty() async throws {
        // Given
        let source = try await ResumableUploadSource(Self.body(of: [Self.bytes(count: 100)]))

        // When
        let remaining = source.remaining(from: 1_000_000_000_000)

        // Then
        #expect(remaining.totalSize == 0)
        #expect(try await remaining.data().isEmpty)
    }

    @Test
    func remaining_canBeReadAgainAndFromAnotherOffset() async throws {
        // Given: what a retry does, over and over, to the same source.
        let payload = Self.bytes(count: 500)
        let source = try await ResumableUploadSource(Self.body(of: [payload]))

        // When
        let first = try await source.remaining(from: 100).data()
        let second = try await source.remaining(from: 100).data()
        let later = try await source.remaining(from: 400).data()
        let whole = try await source.remaining(from: 0).data()

        // Then
        #expect(first == payload.dropFirst(100))
        #expect(second == first)
        #expect(later == payload.dropFirst(400))
        #expect(whole == payload)
    }

    @Test
    func init_whenBodyIsEmpty_hasNoLength() async throws {
        // When
        let source = try await ResumableUploadSource(RequestBody(buffers: []))

        // Then
        #expect(source.length == 0)
        #expect(try await source.remaining(from: 0).data().isEmpty)
    }

    // MARK: - Compressed bodies

    @Test
    func init_whenBodyIsCompressed_declaresTheCompressedLength() async throws {
        // Given
        let payload = Data(String(repeating: "a", count: 100_000).utf8)
        let compressed = try await Self.compressed(payload)

        // When
        let source = try await ResumableUploadSource(compressed)

        // Then: the length is of what goes on the wire, not of the body that was written.
        #expect(source.length < Int64(payload.count))
        #expect(source.length > 0)
        #expect(!source.isBackedByFile)
    }

    @Test(arguments: [0, 1, 17, 100])
    func remaining_whenBodyIsCompressed_isTheSameBytesFromAnyOffset(_ offset: Int) async throws {
        // Given
        let payload = Data(String(repeating: "abc", count: 50_000).utf8)
        let source = try await ResumableUploadSource(Self.compressed(payload))

        // When: whole, then from an offset, each read of its own.
        let whole = try await source.remaining(from: 0).data()
        let rest = try await source.remaining(from: Int64(offset)).data()

        // Then
        #expect(Int64(whole.count) == source.length)
        #expect(rest == whole.dropFirst(offset))
    }

    @Test
    func init_whenCompressedBodyOutgrowsMemory_goesToAFileWithTheSameBytes() async throws {
        // Given: bytes that don't compress, so the result is as large as the input.
        let payload = Self.bytes(count: 200_000, seed: 31, pattern: .noisy)
        let compressed = try await Self.compressed(payload)

        // When
        let small = try await ResumableUploadSource(compressed, memoryLimit: 1_024)
        let large = try await ResumableUploadSource(compressed)

        // Then: only the place it is kept in differs.
        #expect(small.isBackedByFile)
        #expect(!large.isBackedByFile)
        #expect(small.length == large.length)

        let inFile = try await small.remaining(from: 0).data()
        let inMemory = try await large.remaining(from: 0).data()

        #expect(Int64(inFile.count) == small.length)
        #expect(inFile == inMemory)
        #expect(try await small.remaining(from: 150_000).data() == inMemory.dropFirst(150_000))
    }

    // MARK: - RequestBody

    @Test
    func dropping_whenBodyIsCompressing_isNil() async throws {
        // Given
        let compressed = try await Self.compressed(Self.bytes(count: 10_000))

        // Then: its bytes only exist once it is pulled, so there is nothing to skip.
        #expect(compressed.dropping(first: 10) == nil)
    }

    @Test
    func materialized_whenBodyIsAlreadyFixed_isTheSameBody() async throws {
        // Given
        let payload = Self.bytes(count: 100)
        let body = try await Self.body(of: [payload])

        // When
        let materialized = try await body.materialized(memoryLimit: 0)

        // Then
        #expect(try await materialized.data() == payload)
        #expect(!materialized.isBackedByFile)
    }

    // MARK: - Helpers

    private enum Pattern {
        case repeating
        case noisy
    }

    /// Deterministic bytes: the same `seed` always gives the same ones.
    private static func bytes(count: Int, seed: UInt8 = 1, pattern: Pattern = .repeating) -> Data {
        var state = UInt32(seed) &+ 1
        return Data(
            (0..<count).map { index in
                switch pattern {
                case .repeating:
                    return UInt8(truncatingIfNeeded: index &+ Int(seed))
                case .noisy:
                    state = state &* 1_664_525 &+ 1_013_904_223
                    return UInt8(truncatingIfNeeded: state >> 16)
                }
            }
        )
    }

    private static func body(of parts: [Data]) async throws -> RequestBody {
        var buffers: [Internals.AnyBuffer] = []

        for part in parts {
            buffers.append(await Internals.DataBuffer(part))
        }

        return RequestBody(buffers: buffers)
    }

    private static func compressed(_ payload: Data) async throws -> RequestBody {
        var configuration = RequestConfiguration()
        configuration.compression = InternalsCompressionAlgorithmAdapter(algorithm: GzipAlgorithm())
        configuration.body = try await body(of: [payload])

        try configuration.applyCompression()

        return try #require(configuration.body)
    }
}
