//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif
import RequestDL

struct PartForm: Hashable {

    let headers: HTTPHeaders
    let contents: Data
}
