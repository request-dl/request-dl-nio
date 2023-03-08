//
//  ReverseFormData.swift
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

import XCTest
@testable import RequestDL

struct MultipartFormParser {

    let data: Data
    let boundary: String

    init(_ data: Data, boundary: String) {
        self.data = data
        self.boundary = boundary
    }
}

extension MultipartFormParser {

    func parse() throws -> MultipartForm {
        let rawData = try rawData()
        let chunks = try breakIntoChunks(rawData)
        return MultipartForm(
            try chunks.reduce([PartForm]()) {
                $0 + [try partForm($1)]
            },
            boundary: boundary
        )
    }
}

extension MultipartFormParser {

    func rawData() throws -> RawData {
        .init(from: data)
    }

    func breakIntoChunks(_ rawData: RawData) throws -> [[RawData]] {
        var lines = try rawData.split(separator: "\r\n")

        guard (lines.last?.isEmpty ?? false) && rawData.hasSuffix("\r\n") else {
            throw MultipartFormParserError.missingValidFooter
        }

        lines.removeLast()

        guard lines.last == "--\(boundary)--" else {
            throw MultipartFormParserError.missingValidFooter
        }

        lines = lines.dropLast()

        return try lines.reduce([[RawData]]()) {
            if $1 == "--\(boundary)" {
                return $0 + [[$1]]
            } else if let chunk = $0.last {
                return $0.dropLast() + [chunk + [$1]]
            } else {
                throw MultipartFormParserError.invalidLine
            }
        }
    }

    func partForm(_ chunks: [RawData]) throws -> PartForm {
        let chunks = chunks.dropFirst()

        var headersLines: [RawData] = []
        var dataLines: [RawData] = []
        var isReadingDataLines = false

        for line in chunks {
            if isReadingDataLines {
                dataLines.append(line)
            } else if line == "" {
                isReadingDataLines = true
            } else {
                headersLines.append(line)
            }
        }

        guard
            !headersLines.isEmpty,
            !dataLines.isEmpty
        else {
            throw MultipartFormParserError.invalidChunk
        }

        return .init(
            headers: try headers(headersLines),
            contents: dataLines.joined(by: "\r\n").data()
        )
    }
}

extension MultipartFormParser {

    func headers(_ lines: [RawData]) throws -> [String: String] {
        var headers = [String: String]()

        for line in lines {
            var key: String = ""
            var value: String = ""
            var isReadingValues = false

            for character in String(data: line.data(), encoding: .utf8) ?? "" {
                if isReadingValues {
                    value.append(character)
                } else if character == ":" {
                    isReadingValues = true
                } else {
                    key.append(character)
                }
            }

            guard
                !key.isEmpty,
                !value.isEmpty
            else {
                throw MultipartFormParserError.invalidHeaderLine
            }

            if headers[key] != nil {
                throw MultipartFormParserError.duplicatedHeaders
            }

            headers[key] = value.trimmingCharacters(in: .whitespaces)
        }

        guard !headers.isEmpty else {
            throw MultipartFormParserError.invalidHeaders
        }

        return headers
    }
}

extension MultipartFormParser {

    static func extractBoundary(_ string: String?) -> String? {
        let boundary = string?
            .split(separator: ";")
            .last?
            .split(separator: "=")
            .last

        return boundary.map { "\($0)" }?.trimmingCharacters(in: .init(charactersIn: "\""))
    }
}
