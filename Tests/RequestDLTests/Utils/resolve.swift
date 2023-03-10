/*
 See LICENSE for this package's licensing information.
*/

import Foundation
@testable import RequestDL

func resolve<Content: Property>(
    _ content: Content,
    in delegate: DelegateProxy = .init()
) async -> (URLSession, URLRequest) {
    await Resolver(content).make(delegate)
}
