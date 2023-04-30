/*
 See LICENSE for this package's licensing information.
*/

import Foundation

protocol DynamicStoredObject: DynamicValue {

    func update(_ configuration: StoredObjectConfiguration)
}
