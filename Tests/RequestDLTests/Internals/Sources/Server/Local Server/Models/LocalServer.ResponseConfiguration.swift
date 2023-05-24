/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIO
import NIOSSL
import NIOHTTP1
@testable import RequestDL

extension LocalServer {

    struct ResponseConfiguration: Sendable {
        let headers: NIOHTTP1.HTTPHeaders
        let data: Data
    }
}
