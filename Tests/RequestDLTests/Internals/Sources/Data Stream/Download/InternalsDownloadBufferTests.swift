/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct InternalsDownloadBufferTests {

    @Test
    func download_whenAppendingTotalLength_shouldContainsOneFragment() async throws {
        // Given
        let data = Data(repeating: .min, count: 1_024)
        let download = Internals.DownloadBuffer(readingMode: .length(1_024))

        // When
        download.append(Internals.DataBuffer(data))
        download.close()

        // Then
        let bytes = try await Array(Internals.AsyncBytes(
            logger: nil,
            totalSize: data.count,
            stream: download.stream
        ))

        #expect(bytes == [data])
    }

    @Test
    func download_whenAppendingErrorBeforeData_shouldBeEmpty() async throws {
        // Given
        let data = Data(repeating: .min, count: 1_024)
        let download = Internals.DownloadBuffer(readingMode: .length(1_024))

        // When
        download.failed(AnyError())
        download.append(Internals.DataBuffer(data))
        download.close()

        var receivedData = Data()
        var errors = [Error]()

        let bytes = Internals.AsyncBytes(
            logger: nil,
            totalSize: data.count,
            stream: download.stream
        )

        do {
            for try await data in bytes {
                receivedData.append(data)
            }
        } catch {
            errors.append(error)
        }

        // Then
        #expect(receivedData.isEmpty)
        #expect(errors.count == 1)
    }

    @Test
    func download_whenAppendingDifferentSizes_shouldMergeByLength() async throws {
        // Given
        let length = 1_024

        let part1 = Data(repeating: 64, count: length / 2)
        let part2 = Data(repeating: 32, count: length * 3)
        let part3 = Data(repeating: 128, count: length / 4)
        let part4 = Data(repeating: 16, count: length * 2)

        let download = Internals.DownloadBuffer(readingMode: .length(length))

        // When
        download.append(Internals.DataBuffer(part1))
        download.append(Internals.DataBuffer(part2))
        download.append(Internals.DataBuffer(part3))
        download.append(Internals.DataBuffer(part4))
        download.close()

        // Then
        let parts = part1 + part2 + part3 + part4
        let bytes = Internals.AsyncBytes(
            logger: nil,
            totalSize: parts.count,
            stream: download.stream
        )

        let receivedBytes = try await Array(bytes)
        let expectedBytes = Array(parts).split(by: length)

        #expect(receivedBytes == expectedBytes)
    }

    @Test
    func download_whenAppendingWithSplitByByte_shouldContainsFragmentsEndeingWithByte() async throws {
        // Given
        let separator = Data(",".utf8)

        let line1 = Data("0;00;000;0000;00000,".utf8)
        let line2 = Data("1;2;4;8;16,".utf8)
        let line3 = Data("32;64;128;256;512".utf8)

        let download = Internals.DownloadBuffer(readingMode: .separator(Array(separator)))

        // When
        download.append(Internals.DataBuffer(line1 + line2))
        download.append(Internals.DataBuffer(line3))
        download.close()

        // Then
        let parts = line1 + line2 + line3
        let bytes = Internals.AsyncBytes(
            logger: nil,
            totalSize: parts.count,
            stream: download.stream
        )

        let receivedBytes = try await Array(bytes)
        let expectedBytes = Array(parts).split(separator: Array(separator))

        #expect(receivedBytes == expectedBytes)
    }

    @Test
    func download_whenAppendingOnlySeparator_shouldContainsTwoFragments() async throws {
        // Given
        let separator = Data(",".utf8)

        let download = Internals.DownloadBuffer(readingMode: .separator(Array(separator)))

        // When
        download.append(Internals.DataBuffer(separator))
        download.close()

        // Then
        let bytes = Internals.AsyncBytes(
            logger: nil,
            totalSize: separator.count,
            stream: download.stream
        )

        let receivedBytes = try await Array(bytes)
        let expectedBytes = Array(separator).split(separator: Array(separator))

        #expect(receivedBytes == expectedBytes)
    }

    @Test
    func download_whenEmpty_shouldBeEmpty() async throws {
        // Given
        let download = Internals.DownloadBuffer(readingMode: .length(1_024))

        // When
        download.close()

        // Then
        let bytes = Internals.AsyncBytes(
            logger: nil,
            totalSize: .zero,
            stream: download.stream
        )

        let receivedBytes = try await Array(bytes)
        let expectedBytes = [Data]()

        #expect(receivedBytes == expectedBytes)
    }

    @Test
    func download_whenMBAppending_shouldBeEqual() async throws {
        // Given
        let length = 4_096
        let data = Data(repeating: 64, count: 100_000_000)
        let download = Internals.DownloadBuffer(readingMode: .length(length))

        // When
        download.append(Internals.DataBuffer(data))
        download.close()

        // Then
        let bytes = Internals.AsyncBytes(
            logger: nil,
            totalSize: data.count,
            stream: download.stream
        )

        let receivedBytes = try await Array(bytes)
        let expectedBytes = Array(data).split(by: length)

        #expect(receivedBytes == expectedBytes)
    }
}
