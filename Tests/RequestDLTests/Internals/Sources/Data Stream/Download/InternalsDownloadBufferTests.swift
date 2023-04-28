/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

@RequestActor
class InternalsDownloadBufferTests: XCTestCase {

    func testDownload_whenAppendingTotalLength_shouldContainsOneFragment() async throws {
        // Given
        let data = Data(repeating: .min, count: 1_024)
        var download = Internals.DownloadBuffer(readingMode: .length(1_024))

        // When
        download.append(.init(data: data))
        download.close()

        // Then
        let bytes = try await Array(Internals.AsyncBytes(download.stream))

        XCTAssertEqual(bytes, [data])
    }

    func testDownload_whenAppendingErrorBeforeData_shouldBeEmpty() async throws {
        // Given
        let data = Data(repeating: .min, count: 1_024)
        var download = Internals.DownloadBuffer(readingMode: .length(1_024))

        // When
        download.failed(AnyError())
        download.append(.init(data: data))
        download.close()

        var receivedData = Data()
        var errors = [Error]()

        do {
            for try await data in Internals.AsyncBytes(download.stream) {
                receivedData.append(data)
            }
        } catch {
            errors.append(error)
        }

        // Then
        XCTAssertTrue(receivedData.isEmpty)
        XCTAssertEqual(errors.count, 1)
    }

    func testDownload_whenAppendingDifferentSizes_shouldMergeByLength() async throws {
        // Given
        let length = 1_024

        let part1 = Data(repeating: 64, count: length / 2)
        let part2 = Data(repeating: 32, count: length * 3)
        let part3 = Data(repeating: 128, count: length / 4)
        let part4 = Data(repeating: 16, count: length * 2)

        var download = Internals.DownloadBuffer(readingMode: .length(length))

        // When
        download.append(.init(data: part1))
        download.append(.init(data: part2))
        download.append(.init(data: part3))
        download.append(.init(data: part4))
        download.close()

        // Then
        let bytes = try await Array(Internals.AsyncBytes(download.stream))
        let expecting = Array(part1 + part2 + part3 + part4).split(by: length)

        XCTAssertEqual(bytes, expecting)
    }

    func testDownload_whenAppendingWithSplitByByte_shouldContainsFragmentsEndeingWithByte() async throws {
        // Given
        let separator = Data(",".utf8)

        let line1 = Data("0;00;000;0000;00000,".utf8)
        let line2 = Data("1;2;4;8;16,".utf8)
        let line3 = Data("32;64;128;256;512".utf8)

        var download = Internals.DownloadBuffer(readingMode: .separator(Array(separator)))

        // When
        download.append(.init(data: line1 + line2))
        download.append(.init(data: line3))
        download.close()

        // Then
        let bytes = try await Array(Internals.AsyncBytes(download.stream))
        let data = line1 + line2 + line3

        XCTAssertEqual(bytes, Array(data).split(separator: Array(separator)))
    }

    func testDownload_whenAppendingOnlySeparator_shouldContainsTwoFragments() async throws {
        // Given
        let separator = Data(",".utf8)

        var download = Internals.DownloadBuffer(readingMode: .separator(Array(separator)))

        // When
        download.append(.init(data: separator))
        download.close()

        // Then
        let bytes = try await Array(Internals.AsyncBytes(download.stream))
        let data = separator

        XCTAssertEqual(bytes, Array(data).split(separator: Array(separator)))
    }

    func testDownload_whenEmpty_shouldBeEmpty() async throws {
        // Given
        var download = Internals.DownloadBuffer(readingMode: .length(1_024))

        // When
        download.close()

        // Then
        let bytes = try await Array(Internals.AsyncBytes(download.stream))

        XCTAssertTrue(bytes.isEmpty)
    }

    func testDownload_whenMBAppending_shouldBeEqual() async throws {
        // Given
        let length = 4_096
        let data = Data(repeating: 64, count: 100_000_000)
        var download = Internals.DownloadBuffer(readingMode: .length(length))

        // When
        download.append(.init(data: data))
        download.close()

        // Then
        let bytes = try await Array(Internals.AsyncBytes(download.stream))

        XCTAssertEqual(bytes, Array(data).split(by: length))
    }
}
