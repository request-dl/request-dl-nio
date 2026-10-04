//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDLInternals

struct InternalsRequestMetricsCollectorTests {

    private struct FirstError: Error {}
    private struct SecondError: Error {}

    @Test
    func append_returnsWhereEachTransactionWasRecorded() {
        // Given
        let collector = Internals.RequestMetricsCollector()

        // When
        let first = collector.append(.init())
        let second = collector.append(.init())

        // Then
        #expect(first == 0)
        #expect(second == 1)
        #expect(collector.transactions().count == 2)
    }

    @Test
    func setError_setsTheErrorOfTheTransactionAtThatIndex() {
        // Given
        let collector = Internals.RequestMetricsCollector()
        collector.append(.init())
        let index = collector.append(.init())

        // When
        collector.setError(FirstError(), at: index)

        // Then
        let transactions = collector.transactions()
        #expect(transactions[0].error == nil)
        #expect(transactions[1].error is FirstError)
    }

    @Test
    func setError_whenTheTransactionAlreadyHasAnError_leavesItAlone() {
        // Given
        let collector = Internals.RequestMetricsCollector()
        let index = collector.append(.init(error: FirstError()))

        // When
        collector.setError(SecondError(), at: index)

        // Then
        #expect(collector.transactions()[0].error is FirstError)
    }

    @Test
    func setError_whenTheIndexIsOutOfRange_isIgnored() {
        // Given
        let collector = Internals.RequestMetricsCollector()
        collector.append(.init())

        // When
        collector.setError(FirstError(), at: 5)
        collector.setError(FirstError(), at: -1)

        // Then
        #expect(collector.transactions().count == 1)
        #expect(collector.transactions()[0].error == nil)
    }
}
