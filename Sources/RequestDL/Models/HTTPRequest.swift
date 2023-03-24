//
//  File.swift
//
//
//  Created by Brenno on 17/03/23.
//

import Foundation
import AsyncHTTPClient

struct HTTPRequest {

    var url: String
    var method: HTTPMethod
    var headers: Headers
    var body: Body?

    init(url: String) {
        self.url = url
        self.method = .get
        self.headers = .init()
        self.body = nil
    }
}

extension HTTPRequest {

    struct Headers {

        private var headers: [String: String]

        fileprivate init() {
            self.headers = [:]
        }

        mutating func replaceOrAdd(name: String, value: String) {
            headers[name] = value
        }

        fileprivate var arrayOfHeaders: [(String, String)] {
            headers.reduce([(String, String)]()) {
                $0 + [($1.key, $1.value)]
            }
        }
    }
}

extension HTTPRequest {

    enum Body {
        case data(Data)

        func makeHTTPClientBody() -> HTTPClient.Body {
            switch self {
            case .data(let data):
                return .data(data)
            }
        }
    }
}

extension HTTPRequest {

    func makeHTTPClientRequest() throws -> HTTPClient.Request {
        try HTTPClient.Request(
            url: url,
            method: .init(rawValue: method.rawValue),
            headers: .init(headers.arrayOfHeaders),
            body: body?.makeHTTPClientBody()
        )
    }
}
