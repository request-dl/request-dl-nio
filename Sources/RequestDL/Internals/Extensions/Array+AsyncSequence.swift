/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Array {

    init<Sequence: AsyncSequence>(_ sequence: Sequence) async throws where Element == Sequence.Element {
        self.init()

        for try await element in sequence {
            append(element)
        }
    }
}
