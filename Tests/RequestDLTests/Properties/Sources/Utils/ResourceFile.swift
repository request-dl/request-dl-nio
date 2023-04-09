/*
 See LICENSE for this package's licensing information.
*/

import Foundation
@testable import RequestDL

struct ResourceFile {

    let resource: String

    init(_ resource: String) {
        self.resource = resource
    }

    func data() throws -> Data {
        try Data(contentsOf: url())
    }

    func url() throws -> URL {
        guard let url = Bundle.module.resolveURL(forResourceName: resource) else {
            throw FileNotFoundError()
        }

        return url
    }
}

struct FileNotFoundError: Error {}
