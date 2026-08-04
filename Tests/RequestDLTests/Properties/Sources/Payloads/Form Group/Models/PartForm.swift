//
// See LICENSE for this package's licensing information.
//

import RequestDL

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
// import struct Foundation.Data
#endif

struct PartForm: Hashable {

    let headers: HTTPHeaders
    let contents: Data
}
