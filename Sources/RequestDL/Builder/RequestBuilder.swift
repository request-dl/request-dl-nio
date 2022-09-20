import Foundation
import SwiftUI

@resultBuilder
public struct RequestBuilder {

    public static func buildBlock<Content: Request>(_ param: Content) -> Content {
        param
    }

    public static func buildBlock() -> EmptyRequest {
        EmptyRequest()
    }

    public static func buildIf<Content: Request>(_ param: Content?) -> OptionalRequest<Content> {
        OptionalRequest(param)
    }

    public static func buildEither<
        TrueRequest: Request,
        FalseRequest: Request
    >(first: TrueRequest) -> ConditionalRequest<TrueRequest, FalseRequest> {
        ConditionalRequest(trueRequest: first)
    }

    public static func buildEither<
        TrueRequest: Request,
        FalseRequest: Request
    >(second: FalseRequest) -> ConditionalRequest<TrueRequest, FalseRequest> {
        ConditionalRequest(falseRequest: second)
    }

    public static func buildLimitedAvailability<Content: Request>(_ component: Content) -> Content {
        component
    }
}

// swiftlint:disable function_parameter_count identifier_name large_tuple
extension RequestBuilder {

    public static func buildBlock<
        C0: Request,
        C1: Request
    >(
        _ c0: C0,
        _ c1: C1
    ) -> TupleRequest<(C0, C1)> {
        TupleRequest {
            await C0.makeRequest(c0, $0)
            await C1.makeRequest(c1, $0)
        }
    }

    public static func buildBlock<
        C0: Request,
        C1: Request,
        C2: Request
    >(
        _ c0: C0,
        _ c1: C1,
        _ c2: C2
    ) -> TupleRequest<(C0, C1, C2)> {
        TupleRequest {
            await C0.makeRequest(c0, $0)
            await C1.makeRequest(c1, $0)
            await C2.makeRequest(c2, $0)
        }
    }

    public static func buildBlock<
        C0: Request,
        C1: Request,
        C2: Request,
        C3: Request
    >(
        _ c0: C0,
        _ c1: C1,
        _ c2: C2,
        _ c3: C3
    ) -> TupleRequest<(C0, C1, C2, C3)> {
        TupleRequest {
            await C0.makeRequest(c0, $0)
            await C1.makeRequest(c1, $0)
            await C2.makeRequest(c2, $0)
            await C3.makeRequest(c3, $0)
        }
    }

    public static func buildBlock<
        C0: Request,
        C1: Request,
        C2: Request,
        C3: Request,
        C4: Request
    >(
        _ c0: C0,
        _ c1: C1,
        _ c2: C2,
        _ c3: C3,
        _ c4: C4
    ) -> TupleRequest<(C0, C1, C2, C3, C4)> {
        TupleRequest {
            await C0.makeRequest(c0, $0)
            await C1.makeRequest(c1, $0)
            await C2.makeRequest(c2, $0)
            await C3.makeRequest(c3, $0)
            await C4.makeRequest(c4, $0)
        }
    }

    public static func buildBlock<
        C0: Request,
        C1: Request,
        C2: Request,
        C3: Request,
        C4: Request,
        C5: Request
    >(
        _ c0: C0,
        _ c1: C1,
        _ c2: C2,
        _ c3: C3,
        _ c4: C4,
        _ c5: C5
    ) -> TupleRequest<(C0, C1, C2, C3, C4, C5)> {
        TupleRequest {
            await C0.makeRequest(c0, $0)
            await C1.makeRequest(c1, $0)
            await C2.makeRequest(c2, $0)
            await C3.makeRequest(c3, $0)
            await C4.makeRequest(c4, $0)
            await C5.makeRequest(c5, $0)
        }
    }

    public static func buildBlock<
        C0: Request,
        C1: Request,
        C2: Request,
        C3: Request,
        C4: Request,
        C5: Request,
        C6: Request
    >(
        _ c0: C0,
        _ c1: C1,
        _ c2: C2,
        _ c3: C3,
        _ c4: C4,
        _ c5: C5,
        _ c6: C6
    ) -> TupleRequest<(C0, C1, C2, C3, C4, C5, C6)> {
        TupleRequest {
            await C0.makeRequest(c0, $0)
            await C1.makeRequest(c1, $0)
            await C2.makeRequest(c2, $0)
            await C3.makeRequest(c3, $0)
            await C4.makeRequest(c4, $0)
            await C5.makeRequest(c5, $0)
            await C6.makeRequest(c6, $0)
        }
    }

    public static func buildBlock<
        C0: Request,
        C1: Request,
        C2: Request,
        C3: Request,
        C4: Request,
        C5: Request,
        C6: Request,
        C7: Request
    >(
        _ c0: C0,
        _ c1: C1,
        _ c2: C2,
        _ c3: C3,
        _ c4: C4,
        _ c5: C5,
        _ c6: C6,
        _ c7: C7
    ) -> TupleRequest<(C0, C1, C2, C3, C4, C5, C6, C7)> {
        TupleRequest {
            await C0.makeRequest(c0, $0)
            await C1.makeRequest(c1, $0)
            await C2.makeRequest(c2, $0)
            await C3.makeRequest(c3, $0)
            await C4.makeRequest(c4, $0)
            await C5.makeRequest(c5, $0)
            await C6.makeRequest(c6, $0)
            await C7.makeRequest(c7, $0)
        }
    }
}
