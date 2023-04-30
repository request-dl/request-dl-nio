/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/// A namespace for common HTTP headers used in requests and responses.
public enum Headers {}

extension Headers {

    @RequestActor
    struct Node: PropertyNode {
        let key: String
        let value: Any

        func make(_ make: inout Make) async throws {
            let value = "\(value)"
            if !value.isEmpty {
                make.request.headers.setValue(value, forKey: key)
            }
        }
    }
}
