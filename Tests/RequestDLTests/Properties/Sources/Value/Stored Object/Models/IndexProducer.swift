/*
 See LICENSE for this package's licensing information.
*/

import Foundation

class IndexProducer {

    private(set) var index = 0

    func callAsFunction() -> Int {
        let index = index
        self.index += 1
        return index
    }
}
