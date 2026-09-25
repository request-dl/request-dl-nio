//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDLInternals

#if canImport(Darwin)
import Dispatch
import Foundation
import Network

/// Resumes a continuation exactly once from a callback that may fire repeatedly.
private final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var isClaimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isClaimed else { return false }
        isClaimed = true
        return true
    }
}
#endif

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

/// An observer whose `updates()` stream never yields and never finishes on its own; used to
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

/// Models `NWPathMonitor` right after `start()`: `currentPath` still reads its unsatisfied
/// placeholder (confirmed empirically — it only turns satisfied once the first update lands,
/// a few milliseconds later), while the first real path is already on its way.
private struct NotYetResolvedNetworkPathObserver: Internals.NetworkPathObserving {

    let resolvedPath: Internals.NetworkPath

    var currentPath: Internals.NetworkPath {
        disconnectedPath
    }

    func resolvedCurrentPath() async -> Internals.NetworkPath {
        try? await Task.sleep(nanoseconds: 5_000_000)
        return resolvedPath
    }

    func updates() -> _Concurrency.AsyncStream<Internals.NetworkPath> {
        let resolvedPath = resolvedPath
        return _Concurrency.AsyncStream { continuation in
            continuation.yield(resolvedPath)
        }
    }
}

struct InternalsNetworkPathGateTests {

    /// The first gated request in a process used to judge the path from `NWPathMonitor`'s
    /// pre-first-update placeholder, and so failed with `.noConnection` on a fully connected
    /// device whenever `waitsForConnectivity` wasn't also set.
    @Test
    func gate_whenFirstPathNotYetDelivered_judgesTheResolvedPathNotThePlaceholder() async throws {
        // Given
        let observer = NotYetResolvedNetworkPathObserver(resolvedPath: satisfiedPath)
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
    func gate_whenFirstResolvedPathViolatesConstraint_stillThrowsItsReason() async throws {
        // Given
        let observer = NotYetResolvedNetworkPathObserver(resolvedPath: cellularPath)
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
            (error as? Internals.NetworkPathUnsatisfiedError)?.reason == .cellularNotAllowed
        }
    }

    #if canImport(Darwin)
    /// The real monitor's resolved path must be an actual `NWPathMonitor` update, not the
    /// placeholder `currentPath` reads before one arrives: compared against an independent
    /// monitor's own first update, so this holds whether or not the machine is online.
    @Test
    func monitor_resolvedCurrentPath_matchesAFreshMonitorsFirstUpdate() async throws {
        // Given
        let reference = await Self.firstUpdateOfAFreshMonitor()

        // When
        let resolved = await Internals.NetworkPathMonitor.shared.resolvedCurrentPath()

        // Then
        #expect(resolved.isSatisfied == reference)
    }

    private static func firstUpdateOfAFreshMonitor() async -> Bool {
        let monitor = NWPathMonitor()
        defer { monitor.cancel() }

        return await withCheckedContinuation { continuation in
            let once = OnceFlag()
            monitor.pathUpdateHandler = { path in
                if once.claim() {
                    continuation.resume(returning: path.status == .satisfied)
                }
            }
            monitor.start(queue: DispatchQueue(label: "InternalsNetworkPathGateTests.reference"))
        }
    }
    #endif

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
