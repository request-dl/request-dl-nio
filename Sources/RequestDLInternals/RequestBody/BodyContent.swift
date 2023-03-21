/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public protocol BodyContent {

    static func makeBody(_ content: Self, in context: _ContextBody)
}
