/*
 See LICENSE for this package's licensing information.
 */

import Foundation

@RequestActor
public struct _PropertyInputs {
    var environment: EnvironmentValues
    var namespaceID: Namespace.ID
    let seedFactory: SeedFactory
}
