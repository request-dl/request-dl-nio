/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct DynamicValueDeepSearch<Content: Sendable>: Sendable {

    struct Child<Value> {
        let label: String
        let value: Value
    }

    // MARK: - Private properties

    private let mirror: DynamicValueMirror<Content>

    // MARK: - Inits

    init(_ mirror: DynamicValueMirror<Content>) {
        self.mirror = mirror
    }

    // MARK: - Internal methods

    func callAsFunction<Value>(_ type: Value.Type) -> [Child<Value>] {
        mirror().reduce([]) { reduced, child in
            if let value = child.value as? Value {
                return reduced + [.init(
                    label: child.label ?? "_",
                    value: value
                )]
            } else {
                let mirror = DynamicValueMirror(child.value)
                let search = DynamicValueDeepSearch<DynamicValue>(mirror)
                let label = child.label ?? "_"

                return reduced + search(type).map {
                    .init(
                        label: "\(label).\($0.label)",
                        value: $0.value
                    )
                }
            }
        }
    }
}
