/*
 See LICENSE for this package's licensing information.
*/

import Foundation

protocol DynamicEnvironment: DynamicValue {

    func update(_ values: EnvironmentValues)
}
