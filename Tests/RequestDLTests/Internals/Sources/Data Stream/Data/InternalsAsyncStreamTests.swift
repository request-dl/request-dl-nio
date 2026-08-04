//
// See LICENSE for this package's licensing information.
//

import SwiftAsyncStream
import Testing

@testable import RequestDL

struct InternalsDataStreamTests {

    @Test
    func stream_whenInit_shouldBeEmpty() async throws {
        // Given
        let stream = Internals.AsyncStream<Int>()

        let values = InlineProperty(wrappedValue: [Result<Int, Error>]())
        let expectation = AsyncSignal()

        // When
        listenToValues(
            values: values,
            expectation: expectation,
            stream: stream
        )

        stream.close()

        // Then
        try await expectation.wait()

        #expect(values.wrappedValue.isEmpty)
    }

    @Test
    func stream_whenAppendValues_shouldReceiveAll() async throws {
        // Given
        let stream = Internals.AsyncStream<Int>()

        let values = InlineProperty(wrappedValue: [Result<Int, Error>]())
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
        try await expectation.wait()

        #expect(
            try values.wrappedValue.compactMap { try $0.get() } == Array(0...5)
        )
    }

    @Test
    func stream_whenAppendErrorWithValues_shouldReceiveSome() async throws {
        // Given
        let stream = Internals.AsyncStream<Int>()

        let values = InlineProperty(wrappedValue: [Result<Int, Error>]())
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
        try await expectation.wait()

        let _values = values.wrappedValue

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

        let values = InlineProperty(wrappedValue: [Result<Int, Error>]())
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
        try await expectation.wait()

        let _values = values.wrappedValue

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

        let range = 0..<100

        let values = range.map { _ in
            InlineProperty(wrappedValue: [Result<Int, Error>]())
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

        for number in 0..<10 {
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
            try await expectation.wait()
        }

        for value in values {
            #expect(value.wrappedValue.count == 10)
        }
    }

    @Test
    func stream_whenUntilFirstIterationConsumedTwice_shouldReportAlreadyConsumed() async throws {
        // Given
        // `.untilFirstIteration` hands the whole buffer to the first iterator and keeps
        // nothing of its own, so a second iterator has nothing left to replay.
        let stream = Internals.AsyncStream<Int>(bufferingPolicy: .untilFirstIteration)
        stream.append(.success(1))
        stream.close()

        var first = stream.makeAsyncIterator()
        let value = try await first.next()

        // When
        var second = stream.makeAsyncIterator()

        // Then
        #expect(value == 1)
        await #expect(throws: AlreadyConsumedError.self) {
            _ = try await second.next()
        }
    }

    @Test
    func stream_whenIteratingPastDone_shouldKeepReturningNilWithoutCrashing() async throws {
        // Given
        let stream = Internals.AsyncStream<Int>.constant(1)
        var iterator = stream.makeAsyncIterator()

        // When
        let first = try await iterator.next()
        let second = try await iterator.next()
        // The iterator's own state is already `.done` by this third call — not just the
        // underlying subject — exercising that branch directly rather than falling through it.
        let third = try await iterator.next()

        // Then
        #expect(first == 1)
        #expect(second == nil)
        #expect(third == nil)
    }

    @Test
    func stream_equalityAndHashAreIdentityBased() {
        // Given
        let first = Internals.AsyncStream<Int>()
        let second = Internals.AsyncStream<Int>()

        // Then
        #expect(first == first)
        #expect(first != second)

        let set: Set<Internals.AsyncStream<Int>> = [first, first, second]
        #expect(set.count == 2)
    }
}

struct AlreadyConsumedErrorTests {

    @Test
    func descriptionExplainsSingleUseSemantics() {
        #expect(
            AlreadyConsumedError().description
                == """
                This response body has already been consumed. Read it once and keep the result, or \
                issue the request again.
                """
        )
    }
}

extension InternalsDataStreamTests {

    func listenToValues(
        values: InlineProperty<[Result<Int, Error>]>,
        expectation: AsyncSignal,
        stream: Internals.AsyncStream<Int>
    ) {
        _Concurrency.Task {
            do {
                for try await value in stream {
                    var _values = values.wrappedValue
                    _values.append(.success(value))
                    values.wrappedValue = _values
                }
            } catch {
                var _values = values.wrappedValue
                _values.append(.failure(error))
                values.wrappedValue = _values
            }

            expectation.signal()
        }
    }
}
