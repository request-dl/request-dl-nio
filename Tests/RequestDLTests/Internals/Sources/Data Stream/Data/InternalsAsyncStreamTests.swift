/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class InternalsDataStreamTests: XCTestCase {

    var stream: Internals.AsyncStream<Int>!

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
        let values = SendableBox([Result<Int, Error>]())
        let expectation = expectation(description: "empty_stream")

        // When
        listenToValues(
            values: values,
            expectation: expectation
        )

        stream.close()

        // Then
        await _fulfillment(of: [expectation])

        XCTAssertTrue(values().isEmpty)
    }

    func testStream_whenAppendValues_shouldReceiveAll() async throws {
        // Given
        let values = SendableBox<[Result<Int, Error>]>([])
        let expectation = expectation(description: "stream.values")

        // When
        stream.append(.success(0))
        stream.append(.success(1))
        stream.append(.success(2))

        listenToValues(
            values: values,
            expectation: expectation
        )

        stream.append(.success(3))
        stream.append(.success(4))
        stream.append(.success(5))

        stream.close()

        // Then
        await _fulfillment(of: [expectation], timeout: 5)

        XCTAssertEqual(
            try values().compactMap { try $0.get() },
            Array(0...5)
        )
    }

    func testStream_whenAppendErrorWithValues_shouldReceiveSome() async throws {
        // Given
        let values = SendableBox<[Result<Int, Error>]>([])
        let expectation = expectation(description: "stream.values")

        // When
        stream.append(.success(0))

        listenToValues(
            values: values,
            expectation: expectation
        )

        stream.append(.failure(AnyError()))
        stream.append(.success(1))

        // Then
        await _fulfillment(of: [expectation], timeout: 5)

        let _values = values()

        XCTAssertEqual(_values.count, 2)
        XCTAssertEqual(try _values[0].get(), 0)
        XCTAssertThrowsError(try _values[1].get())
    }

    func testStream_whenAppendValuesAndClose_shouldReceiveSome() async throws {
        // Given
        let values = SendableBox<[Result<Int, Error>]>([])
        let expectation = expectation(description: "stream.values")

        // When
        stream.append(.success(0))
        stream.append(.success(1))

        listenToValues(
            values: values,
            expectation: expectation
        )

        stream.close()
        stream.append(.success(2))

        // Then
        await _fulfillment(of: [expectation], timeout: 5)

        let _values = values()

        XCTAssertEqual(_values.count, 2)
        XCTAssertEqual(try _values[0].get(), 0)
        XCTAssertEqual(try _values[1].get(), 1)
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
        for try await value in stream {
            values.append(value)
        }

        // Then
        XCTAssertEqual(values, Array(range))
    }

    func testStream_whenAppendError() async throws {
        // Given
        let error = AnyError()
        var receivedError: Error?

        // When
        stream.append(.failure(error))

        do {
            for try await value in stream {
                XCTFail("Received unexpected \(value)")
            }
        } catch {
            receivedError = error
        }

//         Then
        XCTAssertNotNil(receivedError)
    }

    func testStream_whenCallingMultipleTimesClose() async throws {
        // Given
        var values = [Int]()

        // When
        stream.close()
        stream.close()
        stream.close()

        for try await value in stream {
            values.append(value)
        }

        // Then
        XCTAssertTrue(values.isEmpty)
    }

    func testStream_whenMultipleForEach() async throws {
        // Given
        let range = 0 ..< 100

        let values = range.map { _ in
            SendableBox([Result<Int, Error>]())
        }

        let expectations = range.map {
            expectation(description: "task number #\($0)")
        }

        // When
        for index in range {
            listenToValues(
                values: values[index],
                expectation: expectations[index]
            )
        }

        for number in 0 ..< 10 {
            stream.append(.success(number))

            if number > 7 {
                let error = AnyError()
                stream.append(.failure(error))
                stream.append(.failure(error))
                stream.append(.failure(error))
            }
        }

        stream.close()

        // Then
        await _fulfillment(of: expectations)

        for value in values {
            XCTAssertEqual(value().count, 10)
        }
    }
}

extension InternalsDataStreamTests {

    func listenToValues(
        values: SendableBox<[Result<Int, Error>]>,
        expectation: XCTestExpectation
    ) {
        guard let stream else {
            XCTFail("Found nil stream")
            return
        }
        
        _Concurrency.Task {
            do {
                for try await value in stream {
                    var _values = values()
                    _values.append(.success(value))
                    values(_values)
                }
            } catch {
                var _values = values()
                _values.append(.failure(error))
                values(_values)
            }

            expectation.fulfill()
        }
    }
}
