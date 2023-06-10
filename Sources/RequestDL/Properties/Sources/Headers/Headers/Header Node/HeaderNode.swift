/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct HeaderNode: PropertyNode {

    // MARK: - Internal properties

    let key: String
    let value: String
    let strategy: HeaderStrategy

    // MARK: - Internal methods

    func make(_ make: inout Make) async throws {
        guard !value.isEmpty && !key.isEmpty else {
            return
        }

        switch strategy {
        case .adding:
            make.request.headers.add(name: key, value: value)
        case .setting:
            make.request.headers.set(name: key, value: value)
        }
    }
}
