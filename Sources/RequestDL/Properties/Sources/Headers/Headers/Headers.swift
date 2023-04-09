/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/// A namespace for common HTTP headers used in requests and responses.
public enum Headers {}

extension Headers {

    struct Node: PropertyNode {
        let key: String
        let value: Any
        let next: PropertyNode?

        init(_ value: Any, forKey key: String, next: PropertyNode? = nil) {
            self.key = key
            self.value = value
            self.next = next
        }

        func make(_ make: inout Make) async throws {
            let value = "\(value)"
            if !value.isEmpty {
                make.request.headers.setValue(value, forKey: key)
            }
            try await next?.make(&make)
        }
    }
}
