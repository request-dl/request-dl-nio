//
// See LICENSE for this package's licensing information.
//

protocol GraphValueOperation: Sendable {

    func callAsFunction(_ properties: inout GraphProperties)
}
