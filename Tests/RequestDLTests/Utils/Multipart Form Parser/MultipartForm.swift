/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct MultipartForm {

    let boundary: String
    let items: [PartForm]

    init(_ items: [PartForm], boundary: String) {
        self.boundary = boundary
        self.items = items
    }
}
