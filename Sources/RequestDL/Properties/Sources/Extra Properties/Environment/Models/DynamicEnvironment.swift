//
// See LICENSE for this package's licensing information.
//

protocol DynamicEnvironment: DynamicValue {

    func update(_ values: RequestEnvironmentValues)
}
