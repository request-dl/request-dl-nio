/*
 See LICENSE for this package's licensing information.
*/

import Foundation

protocol NodeObject {

    func makeProperty(_ make: Make) async throws
}
