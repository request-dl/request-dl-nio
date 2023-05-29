/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public struct EncodingPayloadError: Error {

    public enum Context {
        case invalidJSONObject
        case invalidStringEncoding
    }

    // MARK: - Public properties

    public let context: Context

    // MARK: - Inits

    init(_ context: Context) {
        self.context = context
    }
}
