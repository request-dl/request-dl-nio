/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension String {

    func addingRFC3986PercentEncoding() -> String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryRFC3986Allowed) ?? self
    }
}
