/*
 See LICENSE for this package's licensing information.
*/

import Foundation

protocol EnvironmentPropertyValue: PropertyValue {

    func setValue(for values: EnvironmentValues)
}
