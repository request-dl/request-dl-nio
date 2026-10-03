//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL
@testable import RequestDLInternals

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

/// The dialects, so a test that holds for every one of them is written once.
enum ResumableUploadDialectKind: String, CaseIterable, Sendable, CustomTestStringConvertible {
    case ietf
    case tus

    var testDescription: String {
        rawValue
    }

    var dialect: any ResumableUploadDialect {
        switch self {
        case .ietf:
            return IETFResumableUploadDialect()
        case .tus:
            return TUSResumableUploadDialect()
        }
    }
}

enum ResumableUploadDialectFixtures {

    /// What a caller writes for an upload: where it goes, how to authenticate, what it carries.
    static func request(method: String? = "PUT") async -> RequestConfiguration {
        var request = RequestConfiguration()

        request.baseURL = "https://example.com"
        request.pathComponents = ["files", "report.bin"]
        request.queries = [QueryItem(name: "folder", value: "a")]
        request.method = method
        request.headers = [
            "Authorization": "Bearer token",
            "Cookie": "session=1",
            "Content-Type": "application/json",
            "Content-Length": "5",
            "Content-Encoding": "gzip",
        ]
        request.body = await RequestBody(buffers: [Internals.DataBuffer(Data("hello".utf8))])

        return request
    }

    static func head(
        _ code: UInt,
        _ headers: [(String, String)] = []
    ) -> ResponseHead {
        ResponseHead(
            url: nil,
            status: .init(code: code, reason: ""),
            version: .init(minor: 1, major: 1),
            headers: HTTPHeaders(headers),
            isKeepAlive: true
        )
    }

    static let resource = UploadResource(url: "https://example.com/uploads/42")
}
