/*
 See LICENSE for this package's licensing information.
*/

import Foundation

enum MultipartFormParserError: Error {
    case rawDataInvalid
    case missingValidFooter
    case invalidLine
    case invalidChunk
    case invalidHeaderLine
    case invalidHeaders
}

extension MultipartFormParserError: LocalizedError {

    var errorDescription: String? {
        switch self {
        case .rawDataInvalid:
            return "The raw data is invalid and cannot be parsed."
        case .missingValidFooter:
            return "The multipart form data is missing a valid footer."
        case .invalidLine:
            return "The multipart form data contains an invalid line."
        case .invalidChunk:
            return "The multipart form data contains an invalid chunk."
        case .invalidHeaderLine:
            return "The multipart form data contains an invalid header line."
        case .invalidHeaders:
            return "The multipart form data contains invalid headers."
        }
    }
}
