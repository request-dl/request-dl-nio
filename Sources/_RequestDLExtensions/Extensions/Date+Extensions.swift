/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Date {

    public var seconds: Int {
        Int(ceil(Double(timeIntervalSince1970)))
    }
}
