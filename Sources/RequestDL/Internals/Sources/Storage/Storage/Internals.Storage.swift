/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Internals {

    @RequestActor
    class Storage {

        static let lifetime: UInt64 = 5_000_000_000 * 60
        static let shared = Storage(lifetime: lifetime)

        private let lifetime: UInt64
        private var table = [AnyHashable: Register]()

        init(lifetime: UInt64) {
            self.lifetime = lifetime
            scheduleCleanup()
        }

        func setValue<Value>(_ value: Value?, forKey key: AnyHashable) {
            table[key] = value.map {
                .init(value: $0)
            }
        }

        func getValue<Value>(_ type: Value.Type, forKey key: AnyHashable) -> Value? {
            guard let value = table[key]?.value as? Value else {
                return nil
            }

            table[key] = .init(value: value)
            return value
        }
    }
}

extension Internals.Storage {

    fileprivate func scheduleCleanup() {
        _Concurrency.Task(priority: .background) {
            try await _Concurrency.Task.sleep(nanoseconds: UInt64(lifetime))
            cleanupIfNeeded()
            scheduleCleanup()
        }
    }

    private func cleanupIfNeeded() {
        let now = Date()
        let lifetime = Double(lifetime) / 1_000_000_000

        table = table.filter {
            $1.readAt.distance(to: now) <= lifetime
        }
    }
}

extension Internals.Storage {

    fileprivate struct Register {
        let readAt = Date()
        let value: Any
    }
}
