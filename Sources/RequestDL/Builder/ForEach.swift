/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 A request that iterates over a collection of data and creates a request for each element.

 You can use this request to dynamically generate requests based on a collection of data.

 Example:

 ```swift
 let paths = ["user", "search", "results"]

 DataTask {
     BaseURL("ecommerce.com")
     ForEach(paths) {
         Path($0)
     }
 }
 ```
 */
public struct ForEach<Data: Collection, Content: Property>: Property {

    private let data: Data
    private let map: (Data.Element) -> Content

    /**
     Initializes the `ForEach` request with collection of data provided.

     - Parameters:
         - data: The collection of data to iterate over.
         - content: A closure that creates a content for each element of the collection.
     */
    public init(
        _ data: Data,
        @PropertyBuilder content: @escaping (Data.Element) -> Content
    ) {
        self.data = data
        self.map = content
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
        for property in property.data.map(property.map) {
            await Content.makeProperty(property, context)
        }
    }
}
