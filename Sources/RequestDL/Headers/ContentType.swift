//
//  ContentType.swift
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

public enum ContentType {

    case json
    case xml

    case formData

    /**
     The `x-www-form-urlencoded` can be sent via URL parameters or in the body.

     However, the correct submission format to the API must be verified as per `key1=value1&key2=value2`.
     When using Body, use init via String.
     */
    case formURLEncoded

    case text
    case html
    case css
    case javascript

    case gif
    case png
    case jpeg
    case bmp
    case webp

    case midi
    case mpeg
    case wav

    case pdf

    case custom(String)
}

extension ContentType: ExpressibleByStringLiteral {

    public typealias StringLiteralType = String

    public init(stringLiteral value: String) {
        self = .custom(value)
    }
}

extension ContentType: CaseIterable {

    public static var allCases: [ContentType] {
        [
            .json, .xml, .formData, .formURLEncoded,
            .text, .html, .css, .javascript,
            .gif, .png, .jpeg, .bmp, .webp,
            .midi, .mpeg, .wav,
            .pdf
        ]
    }
}

extension ContentType {
    public var rawValue: String {
        switch self {
        case .json:
            return "application/json"
        case .xml:
            return "application/xml"
        case .formData:
            return "form-data"
        case .formURLEncoded:
            return "application/x-www-form-urlencoded"

        case .text:
            return "text/plain"
        case .html:
            return "text/html"
        case .css:
            return "text/css"
        case .javascript:
            return "text/javascript"

        case .gif:
            return "image/gif"
        case .png:
            return "image/png"
        case .jpeg:
            return "image/jpeg"
        case .bmp:
            return "image/bmp"
        case .webp:
            return "image/webp"

        case .midi:
            return "audio/midi"
        case .mpeg:
            return "audio/mpeg"
        case .wav:
            return "audio/wav"

        case .pdf:
            return "application/pdf"

        case .custom(let string):
            return string
        }
    }
}
