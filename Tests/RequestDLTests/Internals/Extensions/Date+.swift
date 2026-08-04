//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
// import struct Foundation.Date
#endif

extension Date {

    /// - Note: `.rounded(.up)`, not the free function `ceil(_:)` — that comes from `Glibc`/
    /// `Darwin`, neither of which this file imports under `FoundationEssentials`.
    var seconds: Int {
        Int(Double(timeIntervalSince1970).rounded(.up))
    }
}
