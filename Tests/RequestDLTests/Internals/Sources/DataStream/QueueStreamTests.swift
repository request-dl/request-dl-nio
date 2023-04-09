/*
 See LICENSE for this package's licensing information.
*/

import XCTest

class QueueStreamTests: XCTestCase {

    var stream: QueueStream<Int>!

    override func setUp() async throws {
        try await super.setUp()
        stream = .init()
    }

    override func tearDown() async throws {
        try await super.tearDown()
        stream = nil
    }

    func testStream_whenAppendValues_shouldContainsAll() async throws {
        // Given
        let range = 0..<10

        // When
        for index in range {
            stream.append(.success(index))
        }

        // Then
        var values = [Int]()

        while let value = try stream.next() {
            values.append(value)
        }

        XCTAssertEqual(values, Array(range))
        XCTAssertTrue(stream.isOpen)
    }

    func testStream_whenAppendNil_shouldBeClosed() async throws {
        // Given
        let range = 0..<10

        // When
        for index in range {
            stream.append(.success(index))
        }

        stream.append(.success(nil))
        stream.append(.success(10))

        // Then
        var values = [Int]()

        while let value = try stream.next() {
            values.append(value)
        }

        XCTAssertEqual(values, Array(range))
        XCTAssertFalse(stream.isOpen)
    }

    func testStream_whenAppendError_shouldThrowError() async throws {
        // Given
        let error = AnyError()

        // When
        stream.append(.failure(error))

        // Then
        XCTAssertThrowsError(try stream.next())
        XCTAssertFalse(stream.isOpen)
    }
}
