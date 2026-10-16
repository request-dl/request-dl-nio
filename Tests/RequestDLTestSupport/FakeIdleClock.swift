//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

/// A clock for `Internals.IdleDeadline` that moves only when a test moves it, and sleeps that end
/// only when it does.
///
/// A test that waits a second of real time for a deadline to run out (or not to) is a test that
/// fails whenever the machine stalls for a second, which a loaded CI runner does. With this, what
/// the deadline sees is exactly what the test said, however the machine runs.
///
/// ```swift
/// let clock = FakeIdleClock()
///
/// let running = Task {
///     try await clock.bind { try await DataTask { ... }.result() }
/// }
///
/// await clock.advance(by: .seconds(60))
/// ```
final class FakeIdleClock: @unchecked Sendable {

    private struct Sleeper {
        let wake: UInt64
        let continuation: CheckedContinuation<Void, any Error>
    }

    // MARK: - Internal properties

    /// What a deadline made under ``bind(_:)`` reads time and waits with.
    var clock: Internals.IdleDeadline.Clock {
        Internals.IdleDeadline.Clock(
            now: { [self] in now.withLockedValue { $0 } },
            sleep: { [self] nanoseconds in
                try await withTaskCancellationHandler {
                    try await withCheckedThrowingContinuation { continuation in
                        let wake = now.withLockedValue { $0 } &+ nanoseconds

                        sleeps.withLockedValue { $0 += 1 }
                        sleepers.withLockedValue { $0.append(Sleeper(wake: wake, continuation: continuation)) }

                        // Cancelled before it was registered: nothing else would end this sleep.
                        if Task.isCancelled {
                            cancelAll()
                        }
                    }
                } onCancel: {
                    cancelAll()
                }
            }
        )
    }

    /// The time, in nanoseconds. Starts well above zero.
    let now = LockedValueBox<UInt64>(1_000_000)

    /// How many sleeps have been started in all.
    var sleepCount: Int {
        sleeps.withLockedValue { $0 }
    }

    /// How many sleeps are waiting right now.
    var sleeperCount: Int {
        sleepers.withLockedValue { $0.count }
    }

    // MARK: - Private properties

    private let sleepers = LockedValueBox<[Sleeper]>([])
    private let sleeps = LockedValueBox(0)

    // MARK: - Inits

    init() {}

    // MARK: - Internal methods

    /// Runs `body` with the deadlines it makes counting this clock's time.
    func bind<T>(_ body: () async throws -> T) async rethrows -> T {
        try await Internals.IdleDeadline.$clock.withValue(clock) {
            try await body()
        }
    }

    /// Waits until something is sleeping on this clock, which is a deadline that has started
    /// counting.
    func waitForASleeper() async {
        await wait(seconds: 10) { sleeperCount > 0 }
    }

    /// Moves time forward by `nanoseconds` and returns once whatever that woke has gone back to
    /// sleep, which is what a deadline does when its budget has not run out.
    ///
    /// - Returns: `false` when nothing was woken, or what was woken did not sleep again: its budget
    ///   ran out (or it ended).
    @discardableResult
    func advance(by nanoseconds: Int64) async -> Bool {
        await waitForASleeper()

        let before = sleepCount
        let woken = wake(after: nanoseconds)

        guard woken > 0 else {
            return false
        }

        await wait { sleepCount >= before + woken }
        return sleepCount >= before + woken
    }

    /// Moves time forward by `nanoseconds` and returns once `deadline`'s watcher has ended, which
    /// is what it does when its budget runs out.
    func advanceUntilDone(_ deadline: Internals.IdleDeadline, by nanoseconds: Int64) async {
        await waitForASleeper()

        let watcher = deadline.watcher
        wake(after: nanoseconds)
        await watcher?.value
    }

    /// The deadline for `nanoseconds` of idle, counting this clock's time.
    func makeDeadline(nanoseconds: Int64) -> Internals.IdleDeadline {
        Internals.IdleDeadline(nanoseconds: nanoseconds, now: clock.now, sleep: clock.sleep)
    }

    /// Moves time forward by `budget` at a time, with a moment of real time in between for what
    /// each step wakes to run, until `isDone`.
    ///
    /// For a transfer that is silent: it ends however late the bytes it was waiting for would
    /// have come.
    func advance(by budget: Int64, until isDone: @Sendable () -> Bool) async {
        let limit = Self.realNow() + 60_000_000_000

        while !isDone(), Self.realNow() < limit {
            wake(after: budget)
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    // MARK: - Private methods

    /// The machine's own time, which is what this class never lets a test depend on, except to
    /// give up waiting.
    private static func realNow() -> UInt64 {
        Internals.IdleDeadline.monotonicNow()
    }

    @discardableResult
    private func wake(after nanoseconds: Int64) -> Int {
        let due = now.withLockedValue { now -> [Sleeper] in
            now = now &+ UInt64(max(nanoseconds, .zero))

            return sleepers.withLockedValue { sleepers in
                let due = sleepers.filter { $0.wake <= now }
                sleepers.removeAll { $0.wake <= now }
                return due
            }
        }

        for sleeper in due {
            sleeper.continuation.resume()
        }

        return due.count
    }

    private func cancelAll() {
        let all = sleepers.withLockedValue { sleepers -> [Sleeper] in
            defer { sleepers = [] }
            return sleepers
        }

        for sleeper in all {
            sleeper.continuation.resume(throwing: CancellationError())
        }
    }

    private func wait(seconds: UInt64 = 30, until condition: () -> Bool) async {
        let limit = Self.realNow() + seconds * 1_000_000_000

        while !condition(), Self.realNow() < limit {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }
}
