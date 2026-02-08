/*
See LICENSE for this package's licensing information.
*/

import Foundation

/**
 A context object providing access to the request configuration within a property or scope.
 */
public struct PropertyContext: Sendable {

    /**
     Provides access to the underlying `RequestConfiguration` object.

     This computed property exposes the configuration details needed for the request.
     */
    public var requestConfiguration: RequestConfiguration {
        make.requestConfiguration
    }

    private let make: Make

    init(_ make: Make) {
        self.make = make
    }
}
