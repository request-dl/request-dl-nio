/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct GraphEnvironmentOperation<Content>: GraphValueOperation {

    private let mirror: DynamicValueMirror<Content>

    init(_ mirror: DynamicValueMirror<Content>) {
        self.mirror = mirror
    }

    func callAsFunction(_ properties: inout GraphProperties) {
        for child in mirror() {
            if let environment = child.value as? DynamicEnvironment {
                environment.update(properties.inputs.environment)
            }
        }
    }
}
