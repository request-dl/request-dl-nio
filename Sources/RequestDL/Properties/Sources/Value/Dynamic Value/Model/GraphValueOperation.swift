/*
 See LICENSE for this package's licensing information.
*/

import Foundation

@RequestActor
protocol GraphValueOperation {

    func callAsFunction(_ properties: inout GraphProperties)
}
