//
// See LICENSE for this package's licensing information.
//

protocol DynamicStoredObject: DynamicValue {

    func update(_ configuration: StoredObjectConfiguration)
}
