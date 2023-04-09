/*
 See LICENSE for this package's licensing information.
*/

import Foundation
@testable import RequestDL

func resolve<Content: Property>(
    _ content: Content
) async throws -> (RequestDLInternals.Session, RequestDLInternals.Request) {
    try await Resolve(content).build()
}
