/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct PartForm {

    let headers: [String: String]
    let contents: Data

    init(
        headers: [String: String],
        contents: Data
    ) {
        self.headers = headers
        self.contents = contents
    }
}
