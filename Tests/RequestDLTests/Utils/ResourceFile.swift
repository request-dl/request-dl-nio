//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import struct Foundation.URL
#endif

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
