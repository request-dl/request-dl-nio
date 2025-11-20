/*
 See LICENSE for this package's licensing information.
*/

import Foundation

private struct HeaderSeparatorKey: RequestEnvironmentKey {
    static let defaultValue: String? = nil
}

extension RequestEnvironmentValues {

    var headerSeparator: String? {
        get { self[HeaderSeparatorKey.self] }
        set { self[HeaderSeparatorKey.self] = newValue }
    }
}

extension Property {

    /**
     Sets the header separator for the property.

     This can be particularly useful if the server does not accept duplicated header keys. By setting the
     separator, the header values will be merged into a single value. This functionality is supported across all
     RequestDL operations.

     The default behavior of SwiftNIO is to send and receive headers value by value. Since this behavior is
     well-suited for SwiftNIO, RequestDL provides the flexibility to change it to meet the specific requirements
     of the server specifications.

     - Parameter headerSeparator: The header separator value. Defaults is `,`.
     - Returns: A modified version of the property with the updated header separator.
     */
    public func headerSeparator(_ headerSeparator: String = ",") -> some Property {
        environment(\.headerSeparator, headerSeparator)
    }
}
