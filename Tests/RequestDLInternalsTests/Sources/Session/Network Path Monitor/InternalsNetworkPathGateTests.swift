//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDLInternals

private struct FakeNetworkPathObserver: Internals.NetworkPathObserving {

    let currentPath: Internals.NetworkPath
    let updateSequence: [Internals.NetworkPath]

    func updates() -> _Concurrency.AsyncStream<Internals.NetworkPath> {
        let sequence = updateSequence
        return _Concurrency.AsyncStream { continuation in
            for path in sequence {
                continuation.yield(path)
            }
            continuation.finish()
        }
    }
}

/// An observer whose `updates()` stream never yields and never finishes on its own -- used to
/// exercise real `Task` cancellation while `NetworkPathGate.wait(for:)` is awaiting it.
private struct HangingNetworkPathObserver: Internals.NetworkPathObserving {

    let currentPath: Internals.NetworkPath

    func updates() -> _Concurrency.AsyncStream<Internals.NetworkPath> {
        _Concurrency.AsyncStream { _ in }
    }
}

private let satisfiedPath = Internals.NetworkPath(
    isSatisfied: true,
    usesCellular: false,
    isExpensive: false,
    isConstrained: false
)

private let cellularPath = Internals.NetworkPath(
    isSatisfied: true,
    usesCellular: true,
    isExpensive: false,
    isConstrained: false
)

private let expensivePath = Internals.NetworkPath(
    isSatisfied: true,
    usesCellular: false,
    isExpensive: true,
    isConstrained: false
)

private let constrainedPath = Internals.NetworkPath(
    isSatisfied: true,
    usesCellular: false,
    isExpensive: false,
    isConstrained: true
)

private let disconnectedPath = Internals.NetworkPath(
    isSatisfied: false,
    usesCellular: false,
    isExpensive: false,
    isConstrained: false
)

struct InternalsNetworkPathGateTests {

    @Test
    func gate_whenPathAlreadySatisfies_shouldReturnImmediately() async throws {
        // Given
        let observer = FakeNetworkPathObserver(currentPath: satisfiedPath, updateSequence: [])
        let constraints = Internals.NetworkPathGate.Constraints(
            allowsCellularAccess: false,
            allowsExpensiveNetworkAccess: nil,
            allowsConstrainedNetworkAccess: nil,
            waitsForConnectivity: nil
        )

        // When / Then
        try await Internals.NetworkPathGate.wait(for: constraints, observer: observer)
    }

    @Test
    func gate_whenCellularViolatedAndNotWaiting_shouldThrowImmediately() async throws {
        // Given
        let observer = FakeNetworkPathObserver(currentPath: cellularPath, updateSequence: [])
        let constraints = Internals.NetworkPathGate.Constraints(
            allowsCellularAccess: false,
            allowsExpensiveNetworkAccess: nil,
            allowsConstrainedNetworkAccess: nil,
            waitsForConnectivity: nil
        )

        // When / Then
        await #expect {
            try await Internals.NetworkPathGate.wait(for: constraints, observer: observer)
        } throws: { error in
            guard let error = error as? Internals.NetworkPathUnsatisfiedError else { return false }
            return error.reason == .cellularNotAllowed && !error.waitedForConnectivity
        }
    }

    @Test
    func gate_whenExpensiveViolatedAndNotWaiting_shouldThrowImmediately() async throws {
        // Given
        let observer = FakeNetworkPathObserver(currentPath: expensivePath, updateSequence: [])
        let constraints = Internals.NetworkPathGate.Constraints(
            allowsCellularAccess: nil,
            allowsExpensiveNetworkAccess: false,
            allowsConstrainedNetworkAccess: nil,
            waitsForConnectivity: nil
        )

        // When / Then
        await #expect {
            try await Internals.NetworkPathGate.wait(for: constraints, observer: observer)
        } throws: { error in
            (error as? Internals.NetworkPathUnsatisfiedError)?.reason == .expensiveNotAllowed
        }
    }

    @Test
    func gate_whenConstrainedViolatedAndNotWaiting_shouldThrowImmediately() async throws {
        // Given
        let observer = FakeNetworkPathObserver(currentPath: constrainedPath, updateSequence: [])
        let constraints = Internals.NetworkPathGate.Constraints(
            allowsCellularAccess: nil,
            allowsExpensiveNetworkAccess: nil,
            allowsConstrainedNetworkAccess: false,
            waitsForConnectivity: nil
        )

        // When / Then
        await #expect {
            try await Internals.NetworkPathGate.wait(for: constraints, observer: observer)
        } throws: { error in
            (error as? Internals.NetworkPathUnsatisfiedError)?.reason == .constrainedNotAllowed
        }
    }

    @Test
    func gate_whenNoConnection_shouldReportNoConnectionReasonRegardlessOfOtherFlags() async throws {
        // Given
        let observer = FakeNetworkPathObserver(currentPath: disconnectedPath, updateSequence: [])
        let constraints = Internals.NetworkPathGate.Constraints(
            allowsCellularAccess: false,
            allowsExpensiveNetworkAccess: false,
            allowsConstrainedNetworkAccess: false,
            waitsForConnectivity: nil
        )

        // When / Then
        await #expect {
            try await Internals.NetworkPathGate.wait(for: constraints, observer: observer)
        } throws: { error in
            (error as? Internals.NetworkPathUnsatisfiedError)?.reason == .noConnection
        }
    }

    @Test
    func gate_whenPathUnsatisfiedButWaits_shouldAwaitUpdateThatSatisfies() async throws {
        // Given
        let observer = FakeNetworkPathObserver(
            currentPath: cellularPath,
            updateSequence: [cellularPath, satisfiedPath]
        )
        let constraints = Internals.NetworkPathGate.Constraints(
            allowsCellularAccess: false,
            allowsExpensiveNetworkAccess: nil,
            allowsConstrainedNetworkAccess: nil,
            waitsForConnectivity: true
        )

        // When / Then
        try await Internals.NetworkPathGate.wait(for: constraints, observer: observer)
    }

    @Test
    func gate_whenObserverFinishesWithoutSatisfying_shouldThrowUnsatisfiedError() async throws {
        // Given
        let observer = FakeNetworkPathObserver(
            currentPath: cellularPath,
            updateSequence: [cellularPath]
        )
        let constraints = Internals.NetworkPathGate.Constraints(
            allowsCellularAccess: false,
            allowsExpensiveNetworkAccess: nil,
            allowsConstrainedNetworkAccess: nil,
            waitsForConnectivity: true
        )

        // When / Then
        await #expect {
            try await Internals.NetworkPathGate.wait(for: constraints, observer: observer)
        } throws: { error in
            guard let error = error as? Internals.NetworkPathUnsatisfiedError else { return false }
            return error.reason == .cellularNotAllowed && error.waitedForConnectivity
        }
    }

    @Test
    func gate_whenCallerTaskCancelledWhileWaiting_shouldThrowCancellationError() async throws {
        // Given
        let observer = HangingNetworkPathObserver(currentPath: cellularPath)
        let constraints = Internals.NetworkPathGate.Constraints(
            allowsCellularAccess: false,
            allowsExpensiveNetworkAccess: nil,
            allowsConstrainedNetworkAccess: nil,
            waitsForConnectivity: true
        )

        let task = Task {
            try await Internals.NetworkPathGate.wait(for: constraints, observer: observer)
        }

        // When
        task.cancel()

        // Then
        await #expect {
            try await task.value
        } throws: { error in
            error is CancellationError
        }
    }

}
