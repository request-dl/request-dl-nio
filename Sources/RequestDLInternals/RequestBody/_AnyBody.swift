/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public struct _AnyBody: BodyContent {

    private let resolve: (_ContextBody) -> Void

    public init<Body: BodyContent>(_ body: Body) {
        resolve = {
            Body.makeBody(body, in: $0)
        }
    }

    public static func makeBody(_ content: Self, in context: _ContextBody) {
        content.resolve(context)
    }
}
