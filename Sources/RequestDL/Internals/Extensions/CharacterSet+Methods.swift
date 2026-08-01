//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import struct FoundationEssentials.CharacterSet
#else
import struct Foundation.CharacterSet
#endif

extension CharacterSet {

    static var urlQueryRFC3986Allowed: CharacterSet {
        CharacterSet.urlQueryAllowed.subtracting(
            CharacterSet(
                charactersIn: ":#[]@!$&'()*+,;="
            )
        )
    }
}
