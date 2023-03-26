/*
 See LICENSE for this package's licensing information.
*/

import Foundation
@testable import RequestDL

func resolve<Content: Property>(
    _ content: Content,
    in delegate: DelegateProxy = .init()
) async throws -> (URLSession, URLRequest) {
    try await Resolver(content).make(delegate)
}
