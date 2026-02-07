/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public struct EndpointError: Error {

    public enum Context: Sendable {
        case invalidURL
        case invalidHost
    }

    public let context: Context
    public let url: String

    public init(
        context: Context,
        url: String
    ) {
        self.context = context
        self.url = url
    }
}
