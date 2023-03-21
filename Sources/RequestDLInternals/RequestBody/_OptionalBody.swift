/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public struct _OptionalBody<Body: BodyContent>: BodyContent {

    private let body: Body?

    init(_ body: Body?) {
        self.body = body
    }

    public static func makeBody(_ content: Self, in context: _ContextBody) {
        if let body = content.body {
            Body.makeBody(body, in: context)
        }
    }
}
