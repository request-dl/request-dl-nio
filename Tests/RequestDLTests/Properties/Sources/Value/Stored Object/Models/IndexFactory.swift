/*
 See LICENSE for this package's licensing information.
*/

import Foundation

protocol IndexFactory: Sendable, AnyObject {

    var rawValue: Int { get }

    init()
}
