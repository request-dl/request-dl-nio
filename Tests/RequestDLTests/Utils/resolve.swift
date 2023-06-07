/*
 See LICENSE for this package's licensing information.
*/

import Foundation
@testable import RequestDL

func resolve<Content: Property>(
    _ content: Content
) async throws -> Resolved {
    try await Resolve(content).build()
}

extension Resolve {

    init(_ root: Root) {
        self.init(root: root, environment: .init())
    }
}
