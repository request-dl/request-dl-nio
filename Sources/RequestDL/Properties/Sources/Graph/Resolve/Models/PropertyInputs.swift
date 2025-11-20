/*
 See LICENSE for this package's licensing information.
 */

import Foundation

public struct _PropertyInputs: Sendable {
    var environment: RequestEnvironmentValues
    var namespaceID: PropertyNamespace.ID
    let seedFactory: SeedFactory
}
