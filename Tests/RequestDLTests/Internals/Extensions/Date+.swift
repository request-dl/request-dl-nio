//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Date
import func Foundation.ceil
#endif

extension Date {

    var seconds: Int {
        Int(ceil(Double(timeIntervalSince1970)))
    }
}
