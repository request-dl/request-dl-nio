//
// See LICENSE for this package's licensing information.
//

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
        // `flatMap` rather than `reduce` with `+`. Appending an array to an accumulator inside
        // a reduce reallocates on every step, which is quadratic in the number of children.
        mirror().flatMap { child -> [Child<Value>] in
            let label = child.label ?? "_"

            if let value = child.value as? Value {
                return [.init(label: label, value: value)]
            }

            let nested = DynamicValueDeepSearch<DynamicValue>(.init(child.value))

            return nested(type).map {
                .init(
                    label: "\(label).\($0.label)",
                    value: $0.value
                )
            }
        }
    }
}
