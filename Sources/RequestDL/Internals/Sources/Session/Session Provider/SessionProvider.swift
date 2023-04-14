/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOCore

protocol SessionProvider {

    var id: String { get }

    func group() -> EventLoopGroup
}
