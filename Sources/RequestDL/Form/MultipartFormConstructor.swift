/*
 See LICENSE for this package's licensing information.
*/

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
        data.append(Data("\(eol)".utf8))

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
