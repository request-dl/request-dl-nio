/*
 See LICENSE for this package's licensing information.
*/

import Foundation

protocol PayloadProvider {

    associatedtype Buffer

    var buffer: Buffer { get }
}
