/*
 See LICENSE for this package's licensing information.
*/

import Foundation

private struct PayloadPartLengthKey: EnvironmentKey {
    static var defaultValue: Int?
}

extension EnvironmentValues {

    var payloadPartLength: Int? {
        get { self[PayloadPartLengthKey.self] }
        set { self[PayloadPartLengthKey.self] = newValue }
    }
}

extension Property {

    /// Sets the length of payload parts to be used during the upload process.
    ///
    /// - Parameter length: The desired length of each payload part.
    /// - Returns: A new instance of Property with the payload part length set.
    public func payloadPartLength(_ length: Int) -> some Property {
        environment(\.payloadPartLength, length)
    }
}
