//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension Date {

    var seconds: Int {
        Int(ceil(Double(timeIntervalSince1970)))
    }
}
