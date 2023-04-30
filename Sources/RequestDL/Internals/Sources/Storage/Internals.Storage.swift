/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Internals {

    @RequestActor
    class Storage {

        static let lifetime: Int = 5_000_000_000
        static let shared = Storage(lifetime: lifetime)

        private let lifetime: Int
        private var table = [AnyHashable: Register]()

        init(lifetime: Int) {
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

        for (key, value) in table {
            if now.timeIntervalSince(value.readAt) > lifetime  {
                table[key] = nil
            }
        }
    }
}

extension Internals.Storage {

    fileprivate struct Register {
        let readAt = Date()
        let value: Any
    }
}
