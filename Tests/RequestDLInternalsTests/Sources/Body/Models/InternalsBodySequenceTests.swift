//
// See LICENSE for this package's licensing information.
//

import SwiftAsyncStream
import Testing

@testable import RequestDLInternals
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import struct Foundation.URL
#endif

struct InternalsBodySequenceTests {

    @Test
    func bodySequence_whenEmpty_shouldBeEmpty() async throws {
        // Given
        let bodySequence = makeBodySequence([])

        // When
        let sequence = try await Array(bodySequence).resolveData()

        // Then
        #expect(sequence == [])
    }

    @Test
    func bodySequence_isEmptyReflectsWhetherBuffersWerePassed() async throws {
        // Given
        let emptyBodySequence = makeBodySequence([])
        let nonEmptyBodySequence = await makeBodySequence([
            Internals.DataBuffer(Data("a".utf8))
        ])

        // Then
        #expect(emptyBodySequence.isEmpty)
        #expect(!nonEmptyBodySequence.isEmpty)
    }

    @Test
    func bodySequence_whenContainsDataLessThenSize_shouldBeEqualData() async throws {
        // Given
        let data = Data("Hello World!".utf8)

        let bodySequence = await makeBodySequence(
            chunkSize: 1024,
            [
                Internals.DataBuffer(data)
            ]
        )

        // When
        let sequence = try await Array(bodySequence).resolveData()

        // Then
        #expect(sequence == [data])
    }

    @Test
    func bodySequence_whenContainsTwoDataLessThenSize_shouldBeEqualParts() async throws {
        // Given
        let part1 = Data("Hello World!".utf8)
        let part2 = Data("Earth is a small planet".utf8)

        let bodySequence = await makeBodySequence(
            chunkSize: 1024,
            [
                Internals.DataBuffer(part1),
                Internals.DataBuffer(part2),
            ]
        )

        // When
        let sequence = try await Array(bodySequence).resolveData()

        // Then
        #expect(sequence == [part1 + part2])
    }

    @Test
    func bodySequence_whenContainsTwoDataGreaterThenSize_shouldBeFragmentedIntoParts() async throws {
        // Given
        let part1 = Data("Hello World!".utf8)
        let part2 = Data("Earth is a small planet".utf8)
        let chunkSize = 2

        let bodySequence = await makeBodySequence(
            chunkSize: chunkSize,
            [
                Internals.DataBuffer(part1),
                Internals.DataBuffer(part2),
            ]
        )

        // When
        let sequence = try await Array(bodySequence).resolveData()
        let expecting = await Array(part1 + part2).split(by: chunkSize)

        // Then
        #expect(sequence == expecting)
    }

    @Test
    func bodySequence_whenContainsFileWithData_shouldContainsAllData() async throws {
        // Given

        let part1 = Data("Hello World!".utf8)
        let part2 = Data("Earth is a small planet".utf8)
        let part3 = Data("Contents in the file".utf8)
        let chunkSize = 16

        let bodySequence = await makeBodySequence(
            chunkSize: chunkSize,
            [
                Internals.DataBuffer(part1),
                Internals.DataBuffer(part2),
                Internals.FileBuffer(part3),
            ]
        )

        // When
        let sequence = try await Array(bodySequence).resolveData()
        let expecting = await Array(part1 + part2 + part3).split(by: chunkSize)

        // Then
        #expect(sequence == expecting)
    }

    @Test
    func bodySequence_whenBiggerDataWithNilSize_shouldFragmentByTheDefaultPolicy() async throws {
        // Given
        let length = 20_001
        let data = await Data.randomData(length: length)

        let bodySequence = await makeBodySequence([
            Internals.DataBuffer(data)
        ])

        // When
        let sequence = try await Array(bodySequence).resolveData()

        // Deriving the expectation from the sequence's own chunk size keeps this about the
        // contract, every byte in order and nothing over the limit, instead of restating the
        // sizing formula and breaking whenever it is tuned.
        let expecting = await Array(data).split(by: bodySequence.chunkSize)

        // Then
        #expect(sequence == expecting)

        // Asserted on purpose and separately from the contract above: twenty kilobytes must not go
        // out as ten thousand two byte chunks.
        #expect(bodySequence.chunkSize == 16 * 1_024)
        #expect(sequence.count == 2)
    }

    /// An explicit non-positive `chunkSize` falls back to `defaultChunkSize`. Taken as-is,
    /// `AsyncIterator.next()`'s `guard chunkSize > .zero` would yield no chunks at all, sending
    /// an empty body under a non-empty declared `totalSize`.
    @Test
    func bodySequence_whenChunkSizeIsZeroOrNegative_fallsBackToDefaultPolicy() async throws {
        // Given
        let length = 100
        let data = await Data.randomData(length: length)

        for invalidChunkSize in [0, -1, -100] {
            let bodySequence = await makeBodySequence(
                chunkSize: invalidChunkSize,
                [Internals.DataBuffer(data)]
            )

            // When
            let sequence = try await Array(bodySequence).resolveData()

            // Then
            #expect(bodySequence.chunkSize > .zero)
            #expect(Data(sequence.joined()) == data)
        }
    }

    /// A file backed `Internals.Buffer` under heavy concurrent I/O must not crash a
    /// `BodySequence` draining it.
    ///
    /// The failure (`Internals.assertionFailure` in `Internals.BodySequence`) never showed up
    /// from a `BodySequence` test run in isolation, only when the buffer was under heavy
    /// concurrent I/O from elsewhere in the process while a `BodySequence` drained it.
    /// `Internals.Buffer.Storage._isResourceAvailable()` retries instead of trusting a single
    /// "unavailable" answer. This pairs `BodySequence` consumption with the same 1,024-way
    /// concurrent pressure `fileBuffer_whenRacingImmutable` applies, both against the one shared
    /// file, so that path has direct coverage instead of only showing up as flakiness.
    @Test
    func bodySequence_whenReadingFileBufferUnderConcurrentPressure_shouldNotReportBug() async throws {
        // Given
        let data = await Data.randomData(length: 128 * 1_024)
        let fileBuffer = await Internals.FileBuffer(data)

        let bodySequence = makeBodySequence(
            chunkSize: 4_096,
            [fileBuffer]
        )

        let capturedAssertions = InlineProperty<[String]>(wrappedValue: [])

        // When
        let chunks = try await Internals.Override.AssertionFailure.replace { message, _, _ in
            capturedAssertions.withValue { $0.append(message) }
        } perform: {
            async let pressure: Void = withTaskGroup(of: Void.self) { group in
                for index in 0..<1_024 {
                    group.addTask {
                        _ = await fileBuffer.getData(at: index, length: data.count - index)
                    }
                }
            }

            let chunks = try await Array(bodySequence)
            await pressure
            return chunks
        }

        // Then
        #expect(capturedAssertions.wrappedValue.isEmpty)
        #expect(chunks.resolveData().reduce(Data(), +) == data)
    }

    /// `AsyncIterator.next()` must not drop consumed buffers with `Array.removeFirst()`, which
    /// shifts every remaining element on every call: O(*n*) per drop, O(*n*²) over a body
    /// assembled from many small parts, exactly the shape a multipart form with many fields
    /// produces (`FormGroupBuilder` emits several tiny buffers per field). This doesn't assert on
    /// timing (flaky under CI load), but a few thousand one-byte buffers still exercise the
    /// index-advancing path, while asserting that every byte comes out in order, nothing dropped
    /// or duplicated.
    @Test
    func bodySequence_whenManySmallBuffers_streamsEveryByteInOrder() async throws {
        // Given
        let byteCount = 4_096
        var buffers: [Internals.AnyBuffer] = []
        for value in 0..<byteCount {
            buffers.append(await Internals.DataBuffer(Data([UInt8(value % 256)])))
        }

        let bodySequence = makeBodySequence(chunkSize: 1024, buffers)

        // When
        let sequence = try await Array(bodySequence).resolveData()
        let combined = sequence.reduce(Data(), +)

        // Then
        let expecting = Data((0..<byteCount).map { UInt8($0 % 256) })
        #expect(combined == expecting)
    }

    /// A file behind a part that is removed after the body was assembled fails the read. Going
    /// on without the part would send a body shorter than the length declared for it.
    @Test
    func bodySequence_whenTheFileBehindAPartIsRemoved_throwsInsteadOfSkippingIt() async throws {
        // Given
        let fileURLManager = try await InternalsFileBufferTests.FileURLManager()
        defer { _ = fileURLManager }

        let fileURL = fileURLManager.url
        try Data(repeating: 0x61, count: 10_000).write(to: fileURL)

        let bodySequence = await makeBodySequence(
            chunkSize: 4_096,
            [
                Internals.DataBuffer(Data("head".utf8)),
                Internals.FileBuffer(fileURL),
                Internals.DataBuffer(Data("tail".utf8)),
            ]
        )

        // When: the file goes away between assembling the body and sending it.
        try await Internals.fileSystem.removeItem(at: fileURL.filePath)

        let captured = InlineProperty<[String]>(wrappedValue: [])

        // Then: reading the body fails, and no assertion trips.
        await #expect(throws: Internals.RequestBodyPartUnreadableError.self) {
            try await Internals.Override.AssertionFailure.replace { message, _, _ in
                captured.withValue { $0.append(message) }
            } perform: {
                _ = try await Array(bodySequence)
            }
        }

        #expect(captured.wrappedValue.isEmpty)
    }

    /// A file that is still there but shorter than when the body was assembled fails the read
    /// too, for the same reason.
    @Test
    func bodySequence_whenTheFileBehindAPartIsCutShort_throwsInsteadOfSendingAShortBody() async throws {
        // Given
        let fileURLManager = try await InternalsFileBufferTests.FileURLManager()
        defer { _ = fileURLManager }

        let fileURL = fileURLManager.url
        try Data(repeating: 0x61, count: 10_000).write(to: fileURL)

        let bodySequence = await makeBodySequence(
            chunkSize: 4_096,
            [
                Internals.DataBuffer(Data("head".utf8)),
                Internals.FileBuffer(fileURL),
                Internals.DataBuffer(Data("tail".utf8)),
            ]
        )

        // When: the file is cut to a hundred bytes between assembling the body and sending it.
        try Data(repeating: 0x61, count: 100).write(to: fileURL)

        // Then
        await #expect(throws: Internals.RequestBodyPartUnreadableError.self) {
            _ = try await Array(bodySequence)
        }
    }

    @Test
    func bodySequence_whenEverythingIsReadable_stillYieldsTheWholeBody() async throws {
        // Given
        let fileURLManager = try await InternalsFileBufferTests.FileURLManager()
        defer { _ = fileURLManager }

        let fileURL = fileURLManager.url
        let content = Data(repeating: 0x62, count: 10_000)
        try content.write(to: fileURL)

        let bodySequence = await makeBodySequence(
            chunkSize: 4_096,
            [
                Internals.DataBuffer(Data("head".utf8)),
                Internals.FileBuffer(fileURL),
                Internals.DataBuffer(Data("tail".utf8)),
            ]
        )

        // When
        let combined = try await Array(bodySequence).resolveData().reduce(Data(), +)

        // Then
        #expect(combined == Data("head".utf8) + content + Data("tail".utf8))
    }

    @Test
    func bodySequence_whenSingleUnreadFileBuffer_wholeFileURLReturnsThatFile() async throws {
        // Given
        let fileURLManager = try await InternalsFileBufferTests.FileURLManager()
        defer { _ = fileURLManager }

        let fileURL = fileURLManager.url
        try Data("Hello world".utf8).write(to: fileURL)

        let bodySequence = await makeBodySequence([Internals.FileBuffer(fileURL)])

        // Then
        #expect(bodySequence.wholeFileURL == fileURL)
    }

    @Test
    func bodySequence_whenSingleDataBuffer_wholeFileURLReturnsNil() async throws {
        // Given
        let bodySequence = await makeBodySequence([Internals.DataBuffer(Data("a".utf8))])

        // Then
        #expect(bodySequence.wholeFileURL == nil)
    }

    @Test
    func bodySequence_whenMultipleBuffersIncludingAFile_wholeFileURLReturnsNil() async throws {
        // Given: mirrors the multipart shape `bodySequence_whenReadingConcurrently...` above
        // builds; a real request body is never *only* the file once there's more than one part.
        let fileURLManager = try await InternalsFileBufferTests.FileURLManager()
        defer { _ = fileURLManager }

        let fileURL = fileURLManager.url
        try Data("part3".utf8).write(to: fileURL)

        let bodySequence = await makeBodySequence([
            Internals.DataBuffer(Data("part1".utf8)),
            Internals.FileBuffer(fileURL),
        ])

        // Then
        #expect(bodySequence.wholeFileURL == nil)
    }

    @Test
    func bodySequence_whenEmpty_wholeFileURLReturnsNil() async throws {
        // Given
        let bodySequence = makeBodySequence([])

        // Then
        #expect(bodySequence.wholeFileURL == nil)
    }
}

extension InternalsBodySequenceTests {

    func makeBodySequence(
        chunkSize: Int? = nil,
        _ buffers: [Internals.AnyBuffer]
    ) -> Internals.BodySequence {
        .init(
            chunkSize: chunkSize,
            buffers: buffers
        )
    }
}
