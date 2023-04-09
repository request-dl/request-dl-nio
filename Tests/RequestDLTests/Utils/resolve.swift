/*
 See LICENSE for this package's licensing information.
*/

import Foundation
@testable import RequestDL

func resolve<Content: Property>(
    _ content: Content
) async throws -> (Internals.Session, Internals.Request) {
    try await Resolve(content).build()
}
