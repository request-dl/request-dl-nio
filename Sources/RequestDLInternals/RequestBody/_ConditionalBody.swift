/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public struct _ConditionalBody<TrueContent: BodyContent, FalseContent: BodyContent>: BodyContent {

    private let condition: Condition

    init(_ trueContent: TrueContent) {
        self.condition = .trueContent(trueContent)
    }

    init(_ falseContent: FalseContent) {
        self.condition = .falseContent(falseContent)
    }

    public static func makeBody(_ content: Self, in context: _ContextBody) {
        switch content.condition {
        case .trueContent(let content):
            TrueContent.makeBody(content, in: context)
        case .falseContent(let content):
            FalseContent.makeBody(content, in: context)
        }
    }
}

extension _ConditionalBody {

    fileprivate enum Condition {
        case trueContent(TrueContent)
        case falseContent(FalseContent)
    }
}
