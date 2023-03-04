//
//  _ConditionalRequest.swift
//
//  MIT License
//
//  Copyright (c) 2022 RequestDL
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

import Foundation

// swiftlint:disable type_name
/// This struct is marked as internal and is not intended
/// to be used directly by clients of this framework.
public struct _ConditionalRequest<
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

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        Never.bodyException()
    }

    /// This method is used internally and should not be called directly.
    public static func makeRequest(_ request: _ConditionalRequest<TrueRequest, FalseRequest>, _ context: Context) async {
        switch request.option {
        case .true(let request):
            await TrueRequest.makeRequest(request, context)
        case .false(let request):
            await FalseRequest.makeRequest(request, context)
        }
    }
}

extension _ConditionalRequest {

    enum Option {
        case `true`(TrueRequest)
        case `false`(FalseRequest)
    }
}
