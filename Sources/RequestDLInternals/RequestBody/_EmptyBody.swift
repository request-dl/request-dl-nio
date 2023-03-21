/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public struct _EmptyBody: BodyContent {

    public static func makeBody(_ content: Self, in context: _ContextBody) {}
}
