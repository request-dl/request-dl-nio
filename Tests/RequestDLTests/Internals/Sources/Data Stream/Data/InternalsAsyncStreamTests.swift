/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct InternalsDataStreamTests {

    @Test
    func stream_whenInit_shouldBeEmpty() async throws {
        // Given
        let stream = Internals.AsyncStream<Int>()

        let values = SendableBox([Result<Int, Error>]())
        let expectation = AsyncSignal()

        // When
        listenToValues(
            values: values,
            expectation: expectation,
            stream: stream
        )

        stream.close()

        // Then
        await expectation.wait()

        #expect(values().isEmpty)
    }

    @Test
    func stream_whenAppendValues_shouldReceiveAll() async throws {
        // Given
        let stream = Internals.AsyncStream<Int>()

        let values = SendableBox<[Result<Int, Error>]>([])
        let expectation = AsyncSignal()

        // When
        stream.append(.success(0))
        stream.append(.success(1))
        stream.append(.success(2))

        listenToValues(
            values: values,
            expectation: expectation,
            stream: stream
        )

        stream.append(.success(3))
        stream.append(.success(4))
        stream.append(.success(5))

        stream.close()

        // Then
        await expectation.wait()

        #expect(
            try values().compactMap { try $0.get() } == Array(0...5)
        )
    }

    @Test
    func stream_whenAppendErrorWithValues_shouldReceiveSome() async throws {
        // Given
        let stream = Internals.AsyncStream<Int>()

        let values = SendableBox<[Result<Int, Error>]>([])
        let expectation = AsyncSignal()

        // When
        stream.append(.success(0))

        listenToValues(
            values: values,
            expectation: expectation,
            stream: stream
        )

        stream.append(.failure(AnyError()))
        stream.append(.success(1))

        // Then
        await expectation.wait()

        let _values = values()

        #expect(_values.count == 2)
        #expect(try _values[0].get() == 0)
        #expect(throws: (any Error).self) {
            try _values[1].get()
        }
    }

    @Test
    func stream_whenAppendValuesAndClose_shouldReceiveSome() async throws {
        // Given
        let stream = Internals.AsyncStream<Int>()

        let values = SendableBox<[Result<Int, Error>]>([])
        let expectation = AsyncSignal()

        // When
        stream.append(.success(0))
        stream.append(.success(1))

        listenToValues(
            values: values,
            expectation: expectation,
            stream: stream
        )

        stream.close()
        stream.append(.success(2))

        // Then
        await expectation.wait()

        let _values = values()

        #expect(_values.count == 2)
        #expect(try _values[0].get() == 0)
        #expect(try _values[1].get() == 1)
    }

    @Test
    func stream_whenAppendingValues_shouldAwaitSequence() async throws {
        // Given
        let stream = Internals.AsyncStream<Int>()

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
        #expect(values == Array(range))
    }

    @Test
    func stream_whenAppendError() async throws {
        // Given
        let stream = Internals.AsyncStream<Int>()

        let error = AnyError()
        var receivedError: Error?

        // When
        stream.append(.failure(error))

        do {
            for try await value in stream {
                Issue.record("Received unexpected \(value)")
            }
        } catch {
            receivedError = error
        }

        // Then
        #expect(receivedError != nil)
    }

    @Test
    func stream_whenCallingMultipleTimesClose() async throws {
        // Given
        let stream = Internals.AsyncStream<Int>()

        var values = [Int]()

        // When
        stream.close()
        stream.close()
        stream.close()

        for try await value in stream {
            values.append(value)
        }

        // Then
        #expect(values.isEmpty)
    }

    @Test
    func stream_whenMultipleForEach() async throws {
        // Given
        let stream = Internals.AsyncStream<Int>()

        let range = 0 ..< 100

        let values = range.map { _ in
            SendableBox([Result<Int, Error>]())
        }

        let expectations = range.map { _ in
            AsyncSignal()
        }

        // When
        for index in range {
            listenToValues(
                values: values[index],
                expectation: expectations[index],
                stream: stream
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
        for expectation in expectations {
            await expectation.wait()
        }

        for value in values {
            #expect(value().count == 10)
        }
    }
}

extension InternalsDataStreamTests {

    func listenToValues(
        values: SendableBox<[Result<Int, Error>]>,
        expectation: AsyncSignal,
        stream: Internals.AsyncStream<Int>
    ) {
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

            expectation.signal()
        }
    }
}
