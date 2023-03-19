/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 A group of header properties that can be applied to a view.

 Use a HeaderGroup to combine multiple header properties into a single property. The properties can be defined
 either directly in the initializer or using a closure with a PropertyBuilder.

 Example:

 ```swift
 HeaderGroup {
     Headers.ContentType(.json)
     Headers.Any("123", forKey: "key")
 }
 ```
 */
public struct HeaderGroup<Content: Property>: Property {

    public typealias Body = Never

    let parameter: Content

    /**
     Initializes a new `HeaderGroup` with a closure that contains the header properties.

     - Parameter parameter: A closure that returns the `Content` containing the header properties.
     */
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

    /**
     Initializes a new `HeaderGroup` with a dictionary of headers.

     - Parameter dictionary: A dictionary containing header properties.
     */
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
                make.request.headers.setValue("\(value)", forKey: key)
            }
        }
    }
}
