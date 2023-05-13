/*
 See LICENSE for this package's licensing information.
*/

import Foundation

protocol PayloadProvider<Buffer>: Sendable {

    associatedtype Buffer: Sendable

    var buffer: Buffer { get }
}
