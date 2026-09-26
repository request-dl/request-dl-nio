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

        // Regression guard, asserted on purpose and separately from the contract above: twenty
        // kilobytes must not go out as ten thousand two byte chunks.
        #expect(bodySequence.chunkSize == 16 * 1_024)
        #expect(sequence.count == 2)
    }

    /// Regression test: an explicit non-positive `chunkSize` used to be taken as-is instead of
    /// falling back to `defaultChunkSize`, so `AsyncIterator.next()`'s `guard chunkSize > .zero`
    /// yielded no chunks at all — an empty body sent under a non-empty declared `totalSize`.
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

    /// Regression test for a fatal crash.
    ///
    /// The crash (`Internals.assertionFailure` at `Internals.BodySequence.swift:75`) never came
    /// from a `BodySequence` test run in isolation — it only ever surfaced when a file backed
    /// `Internals.Buffer` was under heavy concurrent I/O from elsewhere in the process at the
    /// same time a `BodySequence` was draining it, which `Internals.Buffer.Storage.
    /// _isResourceAvailable()` now retries instead of trusting a single "unavailable" answer.
    /// This pairs `BodySequence` consumption with the same 1,024-way concurrent pressure
    /// `fileBuffer_whenRacingImmutable` applies, both against the one shared file, so the fatal
    /// path has direct coverage instead of only showing up as flakiness across the whole suite.
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

    /// Regression test for `AsyncIterator.next()` dropping consumed buffers with
    /// `Array.removeFirst()`, which shifts every remaining element on every call -- O(*n*) per
    /// drop, O(*n*²) over a body assembled from many small parts, exactly the shape a multipart
    /// form with many fields produces (`FormGroupBuilder` emits several tiny buffers per field).
    /// This doesn't assert on timing (flaky under CI load), but a few thousand one-byte buffers
    /// still exercises the same index-advancing path a shift-based implementation would have paid
    /// quadratic cost walking, while asserting the fix didn't change what comes out the other
    /// end: every byte, in order, nothing dropped or duplicated.
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
