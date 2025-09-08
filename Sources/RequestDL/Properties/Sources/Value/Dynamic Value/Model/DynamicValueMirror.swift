/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct DynamicValueMirror<Content: Sendable>: Sendable {

    struct Child {
        let label: String?
        let value: DynamicValue
    }

    // MARK: - Private properties

    private let reflected: @Sendable () -> Mirror

    // MARK: - Inits

    init(_ content: Content) {
        reflected = { Mirror(reflecting: content) }
    }

    // MARK: - Internal methods

    func callAsFunction() -> [Child] {
        reflected().children.compactMap { child in
            (child.value as? DynamicValue).map {
                .init(
                    label: child.label,
                    value: $0
                )
            }
        }
    }
}
