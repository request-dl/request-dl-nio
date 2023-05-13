/*
 See LICENSE for this package's licensing information.
*/

import Foundation

protocol GraphValueOperation: Sendable {

    func callAsFunction(_ properties: inout GraphProperties)
}
