/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct GraphEnvironmentOperation<Content>: GraphValueOperation {

    // MARK: - Private properties

    private let mirror: DynamicValueMirror<Content>

    // MARK: - Inits

    init(_ mirror: DynamicValueMirror<Content>) {
        self.mirror = mirror
    }

    // MARK: - Internal methods

    func callAsFunction(_ properties: inout GraphProperties) {
        for child in mirror() {
            if let environment = child.value as? DynamicEnvironment {
                environment.update(properties.inputs.environment)
            }
        }
    }
}
