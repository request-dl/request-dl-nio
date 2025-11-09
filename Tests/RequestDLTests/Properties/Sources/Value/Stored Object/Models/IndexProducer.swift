/*
 See LICENSE for this package's licensing information.
*/

import Foundation
@testable import RequestDL

class IndexProducer: @unchecked Sendable {

    var index: Int {
        lock.withLock { _index }
    }

    private let lock = Lock()
    private var _index: Int = 0

    func callAsFunction() -> Int {
        lock.withLock {
            let index = _index
            self._index += 1
            return index
        }
    }
}
