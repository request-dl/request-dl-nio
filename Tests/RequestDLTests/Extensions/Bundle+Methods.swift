/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Bundle {

    var normalizedResourceURL: URL {
        if let resourceURL {
            return resourceURL
        }

        return bundleURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("Resource")
    }
}
