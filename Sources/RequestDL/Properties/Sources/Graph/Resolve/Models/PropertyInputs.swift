/*
 See LICENSE for this package's licensing information.
 */

import Foundation

public struct _PropertyInputs {

    var environment: EnvironmentValues
    var namespaceID: Namespace.ID

    init(
        environment: EnvironmentValues
    ) {
        self.environment = environment
        self.namespaceID = .global
    }
}
