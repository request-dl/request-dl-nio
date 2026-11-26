//
// See LICENSE for this package's licensing information.
//

import Foundation
import Testing

@testable import RequestDLInternals

/// `CookieStorage.changes()`: one element per change of what the storage holds, and none for what
/// is not one.
struct InternalsCookieChangesTests {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func url(_ string: String) -> URL {
        URL(string: string)!
    }

    private func cookie(
        _ name: String = "sid",
        value: String = "abc",
        domain: String = "example.com",
        expires: Date? = nil
    ) -> Internals.Cookie {
        Internals.Cookie(
            name: name,
            value: value,
            domain: domain,
            hostOnly: true,
            path: "/",
            expires: expires,
            creation: now
        )
    }

    /// Runs `setup`, observes while `act` runs, and returns how many changes it signaled. The
    /// storage is released at the end, which is what ends the stream and lets it be counted.
    private func signals(
        setup: (Internals.CookieStorage) throws -> Void = { _ in },
        act: (Internals.CookieStorage) throws -> Void
    ) async throws -> Int {
        let stream = try observe(setup: setup, act: act)

        var count = 0
        for await _ in stream {
            count += 1
        }

        return count
    }

    private func observe(
        setup: (Internals.CookieStorage) throws -> Void,
        act: (Internals.CookieStorage) throws -> Void
    ) throws -> AsyncStream<Void> {
        let storage = Internals.CookieStorage()
        try setup(storage)
        let stream = storage.changes(bufferingPolicy: .unbounded)
        try act(storage)
        return stream
    }

    // MARK: - What changes

    @Test
    func changes_whenAResponseSetsACookie_signalsOnce() async throws {
        let count = try await signals { storage in
            storage.store(setCookieValues: ["a=1", "b=2"], for: url("https://example.com/"), now: now)
        }

        #expect(count == 1)
    }

    @Test
    func changes_whenAResponseSetsTheSameCookieAgain_doesNotSignal() async throws {
        let count = try await signals(
            setup: { $0.store(setCookieValues: ["a=1; Max-Age=3600"], for: url("https://example.com/"), now: now) },
            act: { $0.store(setCookieValues: ["a=1; Max-Age=3600"], for: url("https://example.com/"), now: now) }
        )

        #expect(count == 0)
    }

    @Test
    func changes_whenAResponseRenewsAMaxAge_signals() async throws {
        // `Max-Age` is relative to the response, so the expiry it gives is later every time: that
        // is a change (a snapshot would have to save it), as `CookieJar.changes` documents.
        let count = try await signals(
            setup: { $0.store(setCookieValues: ["a=1; Max-Age=3600"], for: url("https://example.com/"), now: now) },
            act: {
                $0.store(
                    setCookieValues: ["a=1; Max-Age=3600"],
                    for: url("https://example.com/"),
                    now: now.addingTimeInterval(2)
                )
            }
        )

        #expect(count == 1)
    }

    @Test
    func changes_whenAResponseSetsTheSameExpiresAgain_doesNotSignal() async throws {
        let value = "a=1; Expires=Wed, 21 Oct 2037 07:28:00 GMT"
        let count = try await signals(
            setup: { $0.store(setCookieValues: [value], for: url("https://example.com/"), now: now) },
            act: {
                $0.store(
                    setCookieValues: [value],
                    for: url("https://example.com/"),
                    now: now.addingTimeInterval(2)
                )
            }
        )

        #expect(count == 0)
    }

    @Test
    func changes_whenAResponseChangesAValueOrAFlag_signals() async throws {
        let count = try await signals(
            setup: { $0.store(setCookieValues: ["a=1"], for: url("https://example.com/"), now: now) },
            act: { storage in
                storage.store(setCookieValues: ["a=2"], for: url("https://example.com/"), now: now)
                storage.store(setCookieValues: ["a=2; HttpOnly"], for: url("https://example.com/"), now: now)
                storage.store(
                    setCookieValues: ["a=2; HttpOnly; Max-Age=10"],
                    for: url("https://example.com/"),
                    now: now
                )
            }
        )

        #expect(count == 3)
    }

    @Test
    func changes_whenAResponseDeletesACookie_signalsAndWhenThereIsNothingToDelete_doesNot() async throws {
        let deleting = try await signals(
            setup: { $0.store(setCookieValues: ["a=1"], for: url("https://example.com/"), now: now) },
            act: { $0.store(setCookieValues: ["a=; Max-Age=0"], for: url("https://example.com/"), now: now) }
        )

        let nothing = try await signals {
            $0.store(setCookieValues: ["a=; Max-Age=0"], for: url("https://example.com/"), now: now)
        }

        #expect(deleting == 1)
        #expect(nothing == 0)
    }

    @Test
    func changes_whenAResponseIsRefused_doesNotSignal() async throws {
        let count = try await signals { storage in
            storage.store(
                setCookieValues: ["a=1; Domain=com", "b=1; Secure"],
                for: url("http://example.com/"),
                now: now
            )
            storage.store(setCookieValues: ["not a cookie"], for: url("https://example.com/"), now: now)
            storage.store(setCookieValues: [], for: url("https://example.com/"), now: now)
        }

        #expect(count == 0)
    }

    @Test
    func changes_whenACookieIsInserted_signalsOnlyWhenItIsNotWhatTheJarHolds() async throws {
        let count = try await signals { storage in
            try storage.insert(cookie(), now: now)
            try storage.insert(cookie(), now: now)
            try storage.insert(cookie(value: "other"), now: now)
        }

        #expect(count == 2)
    }

    @Test
    func changes_whenAnInsertIsRefused_doesNotSignal() async throws {
        let count = try await signals { storage in
            try? storage.insert(cookie(value: "x; y=1"), now: now)
        }

        #expect(count == 0)
    }

    @Test
    func changes_whenAnExpiredCookieIsInserted_signalsOnlyIfItDeletedOne() async throws {
        let expired = cookie(expires: now.addingTimeInterval(-1))

        let deleting = try await signals(
            setup: { try $0.insert(cookie(), now: now) },
            act: { try $0.insert(expired, now: now) }
        )
        let nothing = try await signals { try $0.insert(expired, now: now) }

        #expect(deleting == 1)
        #expect(nothing == 0)
    }

    @Test
    func changes_whenCookiesAreRemoved_signalsOnlyWhenOneWas() async throws {
        let count = try await signals(
            setup: { try $0.insert(cookie("a"), now: now) },
            act: { storage in
                storage.remove(name: "missing", domain: "example.com", path: "/")
                storage.remove(cookie("missing"))
                storage.removeAll(forHost: "other.com", includingSubdomains: true)
                storage.remove(name: "a", domain: "example.com", path: "/")
                storage.remove(name: "a", domain: "example.com", path: "/")
            }
        )

        #expect(count == 1)
    }

    @Test
    func changes_whenAHostIsCleared_signalsOnce() async throws {
        let count = try await signals(
            setup: {
                try $0.insert(cookie("a"), now: now)
                try $0.insert(cookie("b"), now: now)
            },
            act: { $0.removeAll(forHost: "example.com", includingSubdomains: false) }
        )

        #expect(count == 1)
    }

    @Test
    func changes_whenTheJarIsCleared_signalsOnlyWhenItHeldACookieSomeoneCouldSee() async throws {
        let cleared = try await signals(
            setup: { try $0.insert(cookie(), now: now) },
            act: { $0.removeAll(now: now) }
        )
        let empty = try await signals { $0.removeAll(now: now) }
        let onlyExpired = try await signals(
            setup: { try $0.insert(cookie(expires: now.addingTimeInterval(10)), now: now) },
            act: { $0.removeAll(now: now.addingTimeInterval(20)) }
        )

        #expect(cleared == 1)
        #expect(empty == 0)
        #expect(onlyExpired == 0)
    }

    @Test
    func changes_whenCookiesAreRestored_signalsOnlyWhenOneWasAdded() async throws {
        let added = try await signals { $0.restore([cookie("a"), cookie("b")], now: now) }
        let refused = try await signals { $0.restore([cookie("a", value: "x; y")], now: now) }
        let alreadyThere = try await signals(
            setup: { try $0.insert(cookie("a"), now: now) },
            act: { $0.restore([cookie("a", value: "older")], now: now) }
        )

        #expect(added == 1)
        #expect(refused == 0)
        #expect(alreadyThere == 0)
    }

    @Test
    func changes_whenALimitEvictsACookie_signals() async throws {
        let limit = Internals.CookieStorage.maximumCookiesPerDomain

        let count = try await signals(
            setup: { storage in
                for index in 0..<limit {
                    try storage.insert(cookie("c\(index)"), now: now.addingTimeInterval(TimeInterval(index)))
                }
            },
            act: { try $0.insert(cookie("new"), now: now.addingTimeInterval(1_000)) }
        )

        #expect(count == 1)
    }

    // MARK: - What is not a change

    @Test
    func changes_whenCookiesAreReadSentOrExpire_doesNotSignal() async throws {
        let count = try await signals(
            setup: { try $0.insert(cookie(expires: now.addingTimeInterval(10)), now: now) },
            act: { storage in
                _ = storage.cookies(for: url("https://example.com/"), now: now)
                _ = storage.cookieHeader(for: url("https://example.com/"), now: now)
                _ = storage.snapshot(now: now)
                // It expired: the next request purges it, and nobody saw it go.
                _ = storage.cookieHeader(for: url("https://example.com/"), now: now.addingTimeInterval(20))
            }
        )

        #expect(count == 0)
    }

    // MARK: - The stream

    @Test
    func changes_whenSeveralHappenWhileTheConsumerIsBusy_arriveAsOne() async throws {
        let storage = Internals.CookieStorage()
        let stream = storage.changes()

        for index in 0..<10 {
            try storage.insert(cookie("c\(index)"), now: now)
        }

        var iterator = stream.makeAsyncIterator()
        #expect(await iterator.next() != nil)

        try storage.insert(cookie("later"), now: now)
        #expect(await iterator.next() != nil)
    }

    @Test
    func changes_isRegisteredWhenAskedFor_notWhenIterated() async throws {
        let storage = Internals.CookieStorage()
        let stream = storage.changes()

        try storage.insert(cookie(), now: now)

        var iterator = stream.makeAsyncIterator()
        #expect(await iterator.next() != nil)
    }

    @Test
    func changes_whenThereAreSeveralObservers_eachGetsTheChange() async throws {
        let storage = Internals.CookieStorage()
        let (first, second) = (storage.changes(), storage.changes())

        try storage.insert(cookie(), now: now)

        var (a, b) = (first.makeAsyncIterator(), second.makeAsyncIterator())
        #expect(await a.next() != nil)
        #expect(await b.next() != nil)
        #expect(storage.observerCount == 2)
    }

    @Test
    func changes_whenTheStorageIsReleased_theStreamEnds() async throws {
        let stream = try observe(setup: { _ in }, act: { _ in })

        var count = 0
        for await _ in stream {
            count += 1
        }

        #expect(count == 0)
    }

    @Test
    func changes_whenTheConsumerIsCancelled_isNoLongerTracked() async throws {
        let storage = Internals.CookieStorage()
        let stream = storage.changes()
        #expect(storage.observerCount == 1)

        let task = Task {
            for await _ in stream {}
        }

        task.cancel()
        await task.value

        // Termination is reported on the cancelling thread, but give it the time it needs.
        for _ in 0..<100 where storage.observerCount != 0 {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(storage.observerCount == 0)
    }

    @Test
    func changes_whenManyThreadsChangeTheStorage_theLastStateIsAlwaysSeen() async throws {
        let storage = Internals.CookieStorage()
        let stream = storage.changes()
        let lastSeen = Counter()

        // A consumer that does what the API is for: look again at each element.
        let consumer = Task {
            for await _ in stream {
                lastSeen.value = storage.snapshot().count
            }
        }

        await withTaskGroup(of: Void.self) { group in
            for worker in 0..<8 {
                group.addTask {
                    for index in 0..<100 {
                        try? storage.insert(
                            Internals.Cookie(
                                name: "c",
                                value: "1",
                                domain: "h\(worker)-\(index).example.com",
                                hostOnly: true,
                                path: "/",
                                creation: Date()
                            )
                        )
                    }
                }
            }
        }

        let expected = storage.snapshot().count

        // Whatever was merged, the element that follows the last change makes the consumer look once
        // more, and it sees all of them.
        for _ in 0..<300 where lastSeen.value != expected {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        consumer.cancel()
        await consumer.value

        #expect(expected == 800)
        #expect(lastSeen.value == expected)
    }
}

private final class Counter: @unchecked Sendable {

    private let lock = NSLock()
    private var _value = 0

    var value: Int {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _value
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _value = newValue
        }
    }
}
