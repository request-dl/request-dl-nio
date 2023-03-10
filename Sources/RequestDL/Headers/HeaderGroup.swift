/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public struct HeaderGroup<Content: Property>: Property {

    public typealias Body = Never

    let parameter: Content

    public init(@PropertyBuilder parameter: () -> Content) {
        self.parameter = parameter()
    }

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    /// This method is used internally and should not be called directly.
    public static func makeProperty(
        _ property: Self,
        _ context: Context
    ) async {
        let node = Node(
            root: context.root,
            object: EmptyObject(property),
            children: []
        )

        let newContext = Context(node)
        await Content.makeProperty(property.parameter, newContext)

        let parameters = newContext.findCollection(Headers.Object.self).map {
            ($0.key, $0.value)
        }

        context.append(Node(
            root: context.root,
            object: Object(parameters),
            children: []
        ))
    }
}

extension HeaderGroup where Content == ForEach<[String: Any], Headers.`Any`> {

    public init(_ dictionary: [String: Any]) {
        self.init {
            ForEach(dictionary) {
                Headers.Any($0.value, forKey: $0.key)
            }
        }
    }
}

extension HeaderGroup {

    struct Object: NodeObject {

        private let parameters: [(String, Any)]

        init(_ parameters: [(String, Any)]) {
            self.parameters = parameters
        }

        func makeProperty(_ make: Make) {
            for (key, value) in parameters {
                make.request.setValue("\(value)", forHTTPHeaderField: key)
            }
        }
    }
}
