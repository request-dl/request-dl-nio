//
// See LICENSE for this package's licensing information.
//

import SwiftAsyncStream

extension DataCache {

    /// Marks a key as being written for as long as it lives.
    ///
    /// An entry is installed in both tiers when its write is allocated, with whatever has been
    /// written to it so far. A request that arrives before the write is finished would be given
    /// those bytes as if they were the whole response, so
    /// ``DataCache/getCachedData(forKey:policy:)`` answers a miss for a key with a write in
    /// progress.
    ///
    /// `end()` lifts the mark and is called when the write is finished or discarded. If the
    /// token is released without either (a write that was dropped), `deinit` lifts it, so a key
    /// can never stay unreadable for good.
    final class WriteToken: @unchecked Sendable {

        private let lock = Lock()
        private let onEnd: @Sendable () -> Void
        private var isEnded = false

        /// - Parameter onEnd: Lifts the mark. Called once, the first time the token ends.
        init(onEnd: @escaping @Sendable () -> Void) {
            self.onEnd = onEnd
        }

        func end() {
            let shouldEnd = lock.withLock { () -> Bool in
                guard !isEnded else {
                    return false
                }

                isEnded = true
                return true
            }

            if shouldEnd {
                onEnd()
            }
        }

        deinit {
            end()
        }
    }
}
