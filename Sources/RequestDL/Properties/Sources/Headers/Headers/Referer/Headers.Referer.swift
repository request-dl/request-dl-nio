/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Headers {

    /**
     A header that specifies the URL of a resource from which the requested resource was obtained.

     Usage:

     ```swift
     Headers.Referer("https://www.example.com/")
     ```
     */
    public struct Referer: Property {

        // MARK: - Public properties

        /// Returns an exception since `Never` is a type that can never be constructed.
        public var body: Never {
            bodyException()
        }

        // MARK: - Private properties

        private let value: String

        // MARK: - Inits

        /**
         Initialize the `Referer` header with a URL that specifies the resource from which
         the requested resource was obtained.

         - Parameter url: The URL of the resource.
         */
        public init<S: StringProtocol>(_ url: S) {
            self.value = String(url)
        }

        // MARK: - Public static methods

        /// This method is used internally and should not be called directly.
        public static func _makeProperty(
            property: _GraphValue<Headers.Referer>,
            inputs: _PropertyInputs
        ) async throws -> _PropertyOutputs {
            property.assertPathway()
            return .leaf(Headers.Node(
                key: "Referer",
                value: property.value
            ))
        }
    }
}
