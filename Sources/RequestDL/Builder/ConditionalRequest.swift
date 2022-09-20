import Foundation

public struct ConditionalRequest<
    TrueRequest: Request,
    FalseRequest: Request
>: Request {
    let option: Option

    init(trueRequest: TrueRequest) {
        option = .true(trueRequest)
    }

    init(falseRequest: FalseRequest) {
        option = .false(falseRequest)
    }

    public var body: Never {
        Never.bodyException()
    }

    public static func makeRequest(_ request: ConditionalRequest<TrueRequest, FalseRequest>, _ context: Context) async {
        switch request.option {
        case .true(let request):
            await TrueRequest.makeRequest(request, context)
        case .false(let request):
            await FalseRequest.makeRequest(request, context)
        }
    }
}

extension ConditionalRequest {

    enum Option {
        case `true`(TrueRequest)
        case `false`(FalseRequest)
    }
}
