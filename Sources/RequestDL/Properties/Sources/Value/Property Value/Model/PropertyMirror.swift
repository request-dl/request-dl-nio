/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct PropertyMirror<Content> {

    private let content: Content

    init(_ content: Content) {
        self.content = content
    }

    func callAsFunction() -> [PropertyValue] {
        Mirror(reflecting: content).children.compactMap {
            $0.value as? PropertyValue
        }
    }
}
