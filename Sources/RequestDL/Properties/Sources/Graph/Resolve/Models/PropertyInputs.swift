/*
 See LICENSE for this package's licensing information.
 */

import Foundation

public struct _PropertyInputs: Sendable {
    var environment: EnvironmentValues
    var namespaceID: Namespace.ID
    let seedFactory: SeedFactory
}
