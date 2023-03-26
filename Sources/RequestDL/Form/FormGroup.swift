/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import RequestDLInternals

/**
 A type representing an HTTP form with a list of content.

 Use `FormGroup` to represent an HTTP form with a list of content, which can be used in an HTTP request.
 This type conforms to `Property`, allowing it to be composed with other `Property` objects.

 The content of the form is specified using a property builder syntax, allowing you to create a list of
 properties objects.

 ```swift
 FormGroup {
     FormValue("John", forKey: "name")
     FormValue(25, forKey: "age")
 }
 ```
 */
public struct FormGroup<Content: Property>: Property {

    public typealias Body = Never

    let content: Content

    /**
     Initializes a new instance of `Form` with the specified list of properties.

     - Parameters:
        - content: A property builder closure that creates a list of `Property` objects.
     */
    public init(@PropertyBuilder content: () -> Content) {
        self.content = content()
    }

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    /// This method is used internally and should not be called directly.
    public static func makeProperty(
        _ property: Self,
        _ context: Context
    ) async throws {
        let node = Node(
            root: context.root,
            object: EmptyObject(property),
            children: []
        )

        let newContext = Context(node)
        try await Content.makeProperty(property.content, newContext)

        let parameters = newContext
            .findCollection(FormObject.self)
            .map(\.factory)

        context.append(Node(
            root: context.root,
            object: Object(parameters),
            children: []
        ))
    }
}

extension FormGroup {

    struct Object: NodeObject {
        private let multipart: [() -> PartFormRawValue]

        init(_ multipart: [() -> PartFormRawValue]) {
            self.multipart = multipart
        }

        func makeProperty(_ make: Make) {
            let multipart = multipart.map { $0() }

            let constructor = MultipartFormConstructor(multipart)

            make.request.headers.setValue(
                "multipart/form-data; boundary=\"\(constructor.boundary)\"",
                forKey: "Content-Type"
            )

            make.request.body = RequestBody {
                BodyItem(constructor.body)
            }
        }
    }
}
