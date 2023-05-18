/*
 See LICENSE for this package's licensing information.
*/

import Foundation

protocol PayloadFactory: Sendable {

    var contentType: ContentType? { get }

    func callAsFunction() throws -> Internals.AnyBuffer
}
