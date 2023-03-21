/*
 See LICENSE for this package's licensing information.
*/

import Foundation

@resultBuilder
public struct RequestBodyBuilder {

    public static func buildBlock() -> _EmptyBody {
        _EmptyBody()
    }

    public static func buildBlock<Content: BodyContent>(_ component: Content) -> Content {
        component
    }

    public static func buildIf<Content: BodyContent>(_ content: Content?) -> _OptionalBody<Content> {
        _OptionalBody(content)
    }

    public static func buildEither<
        TrueContent: BodyContent,
        FalseContent: BodyContent
    >(first: TrueContent) -> _ConditionalBody<TrueContent, FalseContent> {
        _ConditionalBody<TrueContent, FalseContent>(first)
    }

    public static func buildEither<
        TrueContent: BodyContent,
        FalseContent: BodyContent
    >(second: FalseContent) -> _ConditionalBody<TrueContent, FalseContent> {
        _ConditionalBody<TrueContent, FalseContent>(second)
    }

    public static func buildLimitedAvailability<Content: BodyContent>(_ component: Content) -> Content {
        component
    }
}

extension RequestBodyBuilder {

    public static func buildBlock<
        C0: BodyContent,
        C1: BodyContent
    >(
        _ c0: C0,
        _ c1: C1
    ) -> _TupleBody<(C0, C1)> {
        .init([
            _AnyBody(c0),
            _AnyBody(c1)
        ])
    }

    public static func buildBlock<
        C0: BodyContent,
        C1: BodyContent,
        C2: BodyContent
    >(
        _ c0: C0,
        _ c1: C1,
        _ c2: C2
    ) -> _TupleBody<(C0, C1, C2)> {
        .init([
            _AnyBody(c0),
            _AnyBody(c1),
            _AnyBody(c2)
        ])
    }

    public static func buildBlock<
        C0: BodyContent,
        C1: BodyContent,
        C2: BodyContent,
        C3: BodyContent
    >(
        _ c0: C0,
        _ c1: C1,
        _ c2: C2,
        _ c3: C3
    ) -> _TupleBody<(C0, C1, C2, C3)> {
        .init([
            _AnyBody(c0),
            _AnyBody(c1),
            _AnyBody(c2),
            _AnyBody(c3)
        ])
    }

    public static func buildBlock<
        C0: BodyContent,
        C1: BodyContent,
        C2: BodyContent,
        C3: BodyContent,
        C4: BodyContent
    >(
        _ c0: C0,
        _ c1: C1,
        _ c2: C2,
        _ c3: C3,
        _ c4: C4
    ) -> _TupleBody<(C0, C1, C2, C3, C4)> {
        .init([
            _AnyBody(c0),
            _AnyBody(c1),
            _AnyBody(c2),
            _AnyBody(c3),
            _AnyBody(c4)
        ])
    }


    public static func buildBlock<
        C0: BodyContent,
        C1: BodyContent,
        C2: BodyContent,
        C3: BodyContent,
        C4: BodyContent,
        C5: BodyContent
    >(
        _ c0: C0,
        _ c1: C1,
        _ c2: C2,
        _ c3: C3,
        _ c4: C4,
        _ c5: C5
    ) -> _TupleBody<(C0, C1, C2, C3, C4, C5)> {
        .init([
            _AnyBody(c0),
            _AnyBody(c1),
            _AnyBody(c2),
            _AnyBody(c3),
            _AnyBody(c4),
            _AnyBody(c5)
        ])
    }

    public static func buildBlock<
        C0: BodyContent,
        C1: BodyContent,
        C2: BodyContent,
        C3: BodyContent,
        C4: BodyContent,
        C5: BodyContent,
        C6: BodyContent
    >(
        _ c0: C0,
        _ c1: C1,
        _ c2: C2,
        _ c3: C3,
        _ c4: C4,
        _ c5: C5,
        _ c6: C6
    ) -> _TupleBody<(C0, C1, C2, C3, C4, C5, C6)> {
        .init([
            _AnyBody(c0),
            _AnyBody(c1),
            _AnyBody(c2),
            _AnyBody(c3),
            _AnyBody(c4),
            _AnyBody(c5),
            _AnyBody(c6)
        ])
    }

    public static func buildBlock<
        C0: BodyContent,
        C1: BodyContent,
        C2: BodyContent,
        C3: BodyContent,
        C4: BodyContent,
        C5: BodyContent,
        C6: BodyContent,
        C7: BodyContent
    >(
        _ c0: C0,
        _ c1: C1,
        _ c2: C2,
        _ c3: C3,
        _ c4: C4,
        _ c5: C5,
        _ c6: C6,
        _ c7: C7
    ) -> _TupleBody<(C0, C1, C2, C3, C4, C5, C6, C7)> {
        .init([
            _AnyBody(c0),
            _AnyBody(c1),
            _AnyBody(c2),
            _AnyBody(c3),
            _AnyBody(c4),
            _AnyBody(c5),
            _AnyBody(c6),
            _AnyBody(c7)
        ])
    }
}
