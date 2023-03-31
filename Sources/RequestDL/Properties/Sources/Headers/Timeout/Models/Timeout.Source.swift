/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Timeout {

    /**
     A set of options representing the types of timeout available for each request.

     Use the static properties of this struct to set the timeout interval for requests and resources.

     1. `request`: The timeout request case. The default value is 60s.
     2. `resource`: The timeout resources case. The default value is 7 days in seconds.
     3. `all`: Defines the same timeout interval for both request and resource.

     In the example below, a request is made to the Google's website with the timeout for all types.

     ```swift
     extension GoogleAPI {

         func website() -> DataTask {
             DataTask {
                 BaseURL("google.com")
                 Timeout(60, for: .all)
             }
         }
     }
     ```
     */
    public struct Source: OptionSet {

        /// The timeout interval for the request.
        public static let connect = Source(rawValue: 1 << 0)

        /// The timeout interval for resource which determinate how long
        /// to wait the resource to be transferred.
        public static let read = Source(rawValue: 1 << 1)

        /// Defines same timeout interval for `request` and `resource`
        public static let all: Self = [.connect, .read]

        public let rawValue: Int

        /**
         Initializes a new timeout source with the given raw value.

         - parameter rawValue: The raw value to use for the timeout source.
         */
        public init(rawValue: Int) {
            self.rawValue = rawValue
        }
    }
}
