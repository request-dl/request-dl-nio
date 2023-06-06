/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public protocol RequestTaskInternals: Sendable {

    @_spi(Private)
    var environment: TaskEnvironmentValues { get set }
}
