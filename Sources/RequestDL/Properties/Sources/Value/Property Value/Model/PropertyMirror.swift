/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct PropertyMirror<Content> {

    private let content: Content

    init(_ content: Content) {
        self.content = content
    }

    func callAsFunction() -> [Child] {
        Mirror(reflecting: content).children.compactMap { child in
            (child.value as? PropertyValue).map {
                .init(
                    label: child.label,
                    value: $0
                )
            }
        }
    }
}

extension PropertyMirror {

    struct Child {
        let label: String?
        let value: PropertyValue
    }
}
