/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Timeout {

    /**
     A set of options representing the types of timeout available for each request.

     Use the static properties of this struct to set the timeout interval for requests and resources.

     1. `connect`: The connect timeout case. The default value is 30s.
     2. `read`: The read timeout case.
     3. `all`: Defines the same timeout interval for both connect and read.

     In the example below, a request is made to the Google's website with the timeout for all types.

     ```swift
     DataTask {
         BaseURL("google.com")
         Timeout(.seconds(60), for: .all)
     }
     ```
     */
    public struct Source: OptionSet, Sendable {

        // MARK: - Public static properties

        /// The timeout interval for the connect.
        public static let connect = Source(rawValue: 1 << 0)

        /// The timeout interval for resource which determinate how long
        /// to wait the resource to be transferred.
        public static let read = Source(rawValue: 1 << 1)

        /// Defines same timeout interval for `request` and `resource`
        public static let all: Self = [.connect, .read]

        // MARK: - Public properties

        public let rawValue: UInt8

        // MARK: - Inits

        /**
         Initializes a new timeout source with the given raw value.

         - parameter rawValue: The raw value to use for the timeout source.
         */
        public init(rawValue: UInt8) {
            self.rawValue = rawValue
        }
    }
}
