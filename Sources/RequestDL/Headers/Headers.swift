/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/// A namespace for common HTTP headers used in requests and responses.
public enum Headers {}

extension Headers {

    struct Object: NodeObject {
        let key: String
        let value: Any
        let next: NodeObject?

        init(_ value: Any, forKey key: String, next: NodeObject? = nil) {
            self.key = key
            self.value = value
            self.next = next
        }

        func makeProperty(_ make: Make) {
            let value = "\(value)"
            if !value.isEmpty {
                make.request.headers.replaceOrAdd(name: key, value: value)
            }
            next?.makeProperty(make)
        }
    }
}
