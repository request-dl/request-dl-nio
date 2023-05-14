/*
 See LICENSE for this package's licensing information.
*/

import Foundation

protocol BufferURL: Sendable {

    static var temporaryURL: Self { get }

    var writtenBytes: Int { get }

    func isResourceAvailable() -> Bool

    func createResourceIfNeeded()
}
