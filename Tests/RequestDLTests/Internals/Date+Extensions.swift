/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Date {

    var seconds: Int {
        Int(ceil(Double(timeIntervalSince1970)))
    }
}
