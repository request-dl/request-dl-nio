/*
 See LICENSE for this package's licensing information.
*/

import Foundation

@RequestActor
struct DynamicValueMirror<Content> {

    private let reflected: Mirror

    init(_ content: Content) {
        reflected = Mirror(reflecting: content)
    }

    func callAsFunction() -> [Child] {
        reflected.children.compactMap { child in
            (child.value as? DynamicValue).map {
                .init(
                    label: child.label,
                    value: $0
                )
            }
        }
    }
}

extension DynamicValueMirror {

    struct Child {
        let label: String?
        let value: DynamicValue
    }
}
