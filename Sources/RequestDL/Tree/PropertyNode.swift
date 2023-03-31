/*
 See LICENSE for this package's licensing information.
*/

import Foundation

protocol PropertyNode {

    func make(_ make: inout Make) async throws
}
