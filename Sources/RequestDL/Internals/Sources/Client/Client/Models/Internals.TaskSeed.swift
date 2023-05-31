/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Internals {

    final class TaskSeed: Sendable, Hashable {

        static var withoutCancellation: TaskSeed {
            TaskSeed {}
        }

        private let cancel: @Sendable () -> Void

        init(_ cancel: @escaping @Sendable () -> Void) {
            self.cancel = cancel
        }

        static func == (lhs: Internals.TaskSeed, rhs: Internals.TaskSeed) -> Bool {
            lhs === rhs
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(ObjectIdentifier(self))
        }

        @Sendable
        func callAsFunction() {
            cancel()
        }

        deinit {
            cancel()
        }
    }
}
