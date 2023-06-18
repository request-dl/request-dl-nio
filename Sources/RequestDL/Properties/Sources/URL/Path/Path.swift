/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 The `Path` is used to specify the URL path to reach the endpoint of the request.

 ## Overview

 You can specify as many paths as necessary and even mix different types such as Int, Double, or any other type that conforms to `LosslessStringConvertible`.

 Here's an example with a single specified path:

 ```swift
 // base-url/api/v1
 Path("api/v1")
 ```

 Here's an example with multiple specified paths, combined in the final URL:

 ```swift
 // base-url/api/v1/users/18900
 Path("api/v1")
 Path("users")
 Path(18900)
 ```

 By using the `Path` component, you can easily construct the desired URL path for your request in RequestDL.
 */
public struct Path: Property {

    private struct Node: PropertyNode {

        let path: String

        func make(_ make: inout Make) async throws {
            guard !path.isEmpty else {
                return
            }

            make.request.pathComponents.append(path)
        }
    }

    // MARK: - Public properties

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    // MARK: - Private properties

    private let path: String

    // MARK: - Inits

    /**
     Instantiate the Path with a string.

     - Parameters:
        - path: The string path. Any leading or trailing slashes will be trimmed.
        If you want to include a slash as a part of the path, escape it using a backslash (\\).
     */
    public init<S: StringProtocol>(_ path: S) {
        self.path = String(path)
    }

    /**
     Instantiate the Path with a value that is string convertible.

     - Parameters:
        - path: The path object. If it contains any leading or trailing slashes will be trimmed.
     */
    public init<S: LosslessStringConvertible>(_ path: S) {
        self.path = String(path)
    }

    // MARK: - Public static methods

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<Path>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()

        let path = property.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        return .leaf(Node(path: path))
    }
}
