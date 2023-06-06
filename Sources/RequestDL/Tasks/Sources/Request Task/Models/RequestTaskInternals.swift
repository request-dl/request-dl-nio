/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/// This protocol is marked as internal and is not intended to be used directly by clients of this framework.
public protocol _RequestTaskInternals: Sendable {

    @_spi(Private)
    var environment: TaskEnvironmentValues { get set }
}
