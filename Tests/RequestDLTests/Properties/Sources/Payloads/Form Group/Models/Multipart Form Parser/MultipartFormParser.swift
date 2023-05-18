/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

struct MultipartFormParser {

    let buffers: [Internals.AnyBuffer]
    let boundary: String

    init(_ buffers: [Internals.AnyBuffer], boundary: String) {
        self.buffers = buffers
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
        .init(from: buffers.reduce(Data()) { $0 + ($1.getData() ?? Data()) })
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

    func headers(_ lines: [RawData]) throws -> HTTPHeaders {
        var headers = HTTPHeaders()

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

            headers.add(name: key, value: value)
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
