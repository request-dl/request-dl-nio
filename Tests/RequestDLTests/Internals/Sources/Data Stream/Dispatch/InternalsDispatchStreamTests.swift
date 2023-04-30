/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

@RequestActor
class DispatchStreamTests: XCTestCase {

    var values: [Result<Int?, Error>]!
    var stream: Internals.DispatchStream<Int>!

    override func setUp() async throws {
        try await super.setUp()
        values = []
        stream = .init {
            self.values.append($0)
        }
    }

    override func tearDown() async throws {
        try await super.tearDown()
        values = nil
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
        XCTAssertEqual(try values.map { try $0.get() }, Array(range))
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

        // Then
        XCTAssertEqual(
            try values.map { try $0.get() },
            Array(range) + [nil]
        )

        XCTAssertFalse(stream.isOpen)
    }

    func testStream_whenAppendError_shouldThrowError() async throws {
        // Given
        let error = AnyError()

        // When
        stream.append(.failure(error))

        // Then
        XCTAssertThrowsError(try values.map { try $0.get() })
        XCTAssertFalse(stream.isOpen)
    }

    func testStream_whenAppendValue_shouldNextBeNil() async throws {
        // Given
        let value = 1

        // When
        stream.append(.success(value))

        // Then
        XCTAssertEqual(try values.map { try $0.get() }, [value])
        XCTAssertNil(try stream.next())
    }
}
