/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension CharacterSet {

    static var urlQueryRFC3986Allowed: CharacterSet {
        CharacterSet.urlQueryAllowed.subtracting(CharacterSet(
            charactersIn: ":#[]@!$&'()*+,;="
        ))
    }
}
