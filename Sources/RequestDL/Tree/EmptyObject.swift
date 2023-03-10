/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct EmptyObject<Content: Property>: NodeObject {

    private let content: Content

    init(_ content: Content) {
        self.content = content
    }

    func makeProperty(_ make: Make) {}
}
