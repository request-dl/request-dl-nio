/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/// A namespace for common HTTP headers used in requests and responses.
public enum Headers {}

extension Headers {

    struct Node: PropertyNode {

        // MARK: - Internal properties

        let key: String
        let value: String

        // MARK: - Internal methods

        func make(_ make: inout Make) async throws {
            if !value.isEmpty {
                make.request.headers.setValue(value, forKey: key)
            }
        }
    }
}
