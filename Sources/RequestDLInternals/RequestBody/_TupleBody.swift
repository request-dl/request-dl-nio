/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public struct _TupleBody<Tuple>: BodyContent {

    private let items: [_AnyBody]

    init(_ items: [_AnyBody]) {
        self.items = items
    }

    public static func makeBody(_ content: Self, in context: _ContextBody) {
        for item in content.items {
            _AnyBody.makeBody(item, in: context)
        }
    }
}
