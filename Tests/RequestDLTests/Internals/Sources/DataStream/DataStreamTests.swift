/*
 See LICENSE for this package's licensing information.
*/

import XCTest

class DataStreamTests: XCTestCase {

    var stream: DataStream<Int>!

    override func setUp() async throws {
        try await super.setUp()
        stream = .init()
    }

    override func tearDown() async throws {
        try await super.tearDown()
        stream = nil
    }

    func testStream_whenInit_shouldBeEmpty() async throws {
        // Given
        var values: [Result<Int?, Error>] = []

        // When
        stream.observe {
            values.append($0)
        }

        // Then
        XCTAssertTrue(values.isEmpty)
    }

    func testStream_whenAppendValues_shouldReceiveAll() async throws {
        // Given
        var values: [Result<Int?, Error>] = []
        let expectation = expectation(description: "stream.values")

        expectation.expectedFulfillmentCount = 6

        // When
        stream.append(.success(0))
        stream.append(.success(1))
        stream.append(.success(2))

        stream.observe {
            values.append($0)
            expectation.fulfill()
        }

        stream.append(.success(3))
        stream.append(.success(4))
        stream.append(.success(5))

        // Then
        await fulfillment(of: [expectation], timeout: 5)

        XCTAssertEqual(
            try values.compactMap { try $0.get() },
            Array(0...5)
        )
    }

    func testStream_whenAppendErrorWithValues_shouldReceiveSome() async throws {
        // Given
        var values: [Result<Int?, Error>] = []
        let expectation = expectation(description: "stream.values")

        expectation.expectedFulfillmentCount = 2

        // When
        stream.append(.success(0))

        stream.observe {
            values.append($0)
            expectation.fulfill()
        }

        stream.append(.failure(AnyError()))
        stream.append(.success(1))

        // Then
        await fulfillment(of: [expectation], timeout: 5)

        XCTAssertEqual(values.count, 2)
        XCTAssertEqual(try values[0].get(), 0)
        XCTAssertThrowsError(try values[1].get())
    }

    func testStream_whenAppendValuesAndClose_shouldReceiveSome() async throws {
        // Given
        var values: [Result<Int?, Error>] = []
        let expectation = expectation(description: "stream.values")

        expectation.expectedFulfillmentCount = 3

        // When
        stream.append(.success(0))
        stream.append(.success(1))

        stream.observe {
            values.append($0)
            expectation.fulfill()
        }

        stream.close()
        stream.append(.success(2))

        // Then
        await fulfillment(of: [expectation], timeout: 5)

        XCTAssertEqual(values.count, 3)
        XCTAssertEqual(try values[0].get(), 0)
        XCTAssertEqual(try values[1].get(), 1)
        XCTAssertNil(try values[2].get())
    }

    func testStream_whenAppendingValues_shouldAwaitSequence() async throws {
        // Given
        let range = 0..<3

        for value in range {
            stream.append(.success(value))
        }

        stream.close()

        // When
        var values: [Int] = []
        for try await value in stream.asyncStream() {
            values.append(value)
        }

        // Then
        XCTAssertEqual(values, Array(range))
    }
}
