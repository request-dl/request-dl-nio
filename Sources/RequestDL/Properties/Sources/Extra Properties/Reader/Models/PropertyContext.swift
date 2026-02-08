/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public struct PropertyContext: Sendable {

    public var requestConfiguration: RequestConfiguration {
        make.requestConfiguration
    }

    private let make: Make

    init(_ make: Make) {
        self.make = make
    }
}
