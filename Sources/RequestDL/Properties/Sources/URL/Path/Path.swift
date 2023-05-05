/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 Use Path to specify the URL pathway.

 You can have multiple Paths inside the body or @PropertyBuilder results,
 which will be combined in to a single Path appended at BaseURL.

 Example of single path:

 ```swift
 struct AppleDeveloperDefaultPaths: Property {

     var body: some Property {
         Path("api/v2/ios")
     }
 }
 ```

 Example of multiple paths:

 ```swift
 struct AppleDeveloperDefaultPaths: Property {

     var body: some Property {
         Path("api")
         Path("v2")
         Path("ios")
     }
 }
 ```

 The resulting URL from multiple paths is the concatenation of all paths,
 appended at the BaseURL. If any path has a leading or trailing slash, it will
 be trimmed. If you want to include a slash as a part of the path, you can
 escape it using a backslash (\\).

 ```swift
 struct ExampleRequest: Property {

     var body: some Property {
         Path("users")
         Path("1234")
         Path("\\/posts")
     }
 }

 The resulting URL of the above request would be `BaseURL/users/1234\/posts`.
 ```
 */
@RequestActor
public struct Path: Property {

    private let path: String

    /**
     Instantiate the Path with a string.

     - Parameters:
        - path: The string path. Any leading or trailing slashes will be trimmed.
        If you want to include a slash as a part of the path, escape it using a backslash (\\).
     */
    public init(_ path: String) {
        self.path = path
    }

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }
}

extension Path {

    private struct Node: PropertyNode {

        let path: String

        func make(_ make: inout Make) async throws {
            guard !path.isEmpty else {
                return
            }

            make.request.pathComponents.append(path)
        }
    }

    /// This method is used internally and should not be called directly.
    @RequestActor
    public static func _makeProperty(
        property: _GraphValue<Path>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()

        let path = property.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        return .leaf(Node(path: path))
    }
}
