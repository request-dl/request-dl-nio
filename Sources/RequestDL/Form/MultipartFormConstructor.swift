//
//  MultipartFormConstructor.swift
//
//  MIT License
//
//  Copyright (c) RequestDL
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

struct MultipartFormConstructor {

    let boundary: String
    let multipart: [PartFormRawValue]

    fileprivate init(_ boundary: String, multipart: [PartFormRawValue]) {
        self.boundary = boundary
        self.multipart = multipart
    }

    var body: Data {
        let header = Data("--\(boundary)\(eol)".utf8)

        let multipart = multipart.map {
            var data = header
            data.append(buildData(for: $0))
            return data
        }

        var data = Data()

        for part in multipart {
            data.append(part)
            data.append(Data("\(eol)".utf8))
        }

        data.append(Data("--\(boundary)--".utf8))

        return data
    }
}

extension MultipartFormConstructor {

    fileprivate func buildData(for multipart: PartFormRawValue) -> Data {
        let headers = multipart.headers
            .reduce([String]()) { $0 + ["\($1.key): \($1.value)"] }
            .joined(separator: "\(eol)")

        var data = Data("\(headers)\(eol)".utf8)
        data.append(Data("\(eol)".utf8))
        data.append(multipart.data)
        return data
    }
}

extension MultipartFormConstructor {

    var eol: Character {
        "\r\n"
    }
}

extension MultipartFormConstructor {

    private static var boundary: String {
        let prefix = UInt64.random(in: .min ... .max)
        let sufix = UInt64.random(in: .min ... .max)

        return "\(String(prefix, radix: 16)):\(String(sufix, radix: 16))"
    }

    init(_ multipart: [PartFormRawValue]) {
        self.init(Self.boundary, multipart: multipart)
    }
}
