/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import RequestDL

struct PartForm: Hashable {

    let headers: HTTPHeaders
    let contents: Data

    init(
        headers: HTTPHeaders,
        contents: Data
    ) {
        self.headers = headers
        self.contents = contents
    }
}
