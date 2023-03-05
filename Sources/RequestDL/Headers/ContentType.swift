//
//  ContentType.swift
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

/**
 The ContentType struct is used to define the media type of the data in the HTTP request.

 Usage:

 ```swift
 let contentType: ContentType = .json
 ```

 - Note: For a complete list of the available types, please see the corresponding static
 properties.

 - Important: If the media type is not included in the predefined static properties, use
 a string literal to initialize an instance of ContentType.

 The ContentType struct conforms to the `ExpressibleByStringLiteral` protocol, allowing
 it to be initialized with a string literal, like so:

 ```swift
 let customContentType: ContentType = "application/custom"
 ```
 */
public struct ContentType {

    let rawValue: String

    /**
     Initializes a `ContentType` instance with a given string value.

     - Parameter rawValue: The string value of the content type.
     */
    public init<S: StringProtocol>(_ rawValue: S) {
        self.rawValue = String(rawValue)
    }
}

extension ContentType {

    /// Content type for JSON data.
    public static let json: ContentType = "application/json"

    /// Content type for XML data.
    public static let xml: ContentType = "application/xml"

    /// Content type for form data with files.
    public static let formData: ContentType = "form-data"

    /**
     Content type for form data in the `x-www-form-urlencoded` format.

     This type can be sent via URL parameters or in the body, but the correct submission format to
     the API must be verified as per `key1=value1&key2=value2`.

     - Warning: When using `Payload`, use init via String.
     */
    public static let formURLEncoded: ContentType = "application/x-www-form-urlencoded"

    /// Content type for plain text data.
    public static let text: ContentType = "text/plain"

    /// Content type for HTML data.
    public static let html: ContentType = "text/html"

    /// Content type for CSS data.
    public static let css: ContentType = "text/css"

    /// Content type for JavaScript data.
    public static let javascript: ContentType = "text/javascript"

    /// Content type for GIF images.
    public static let gif: ContentType = "image/gif"

    /// Content type for PNG images.
    public static let png: ContentType = "image/png"

    /// Content type for JPEG images.
    public static let jpeg: ContentType = "image/jpeg"

    /// Content type for BMP images.
    public static let bmp: ContentType = "image/bmp"

    /// Content type for WebP images.
    public static let webp: ContentType = "image/webp"

    /// Content type for MIDI audio.
    public static let midi: ContentType = "audio/midi"

    /// Content type for MPEG audio.
    public static let mpeg: ContentType = "audio/mpeg"

    /// Content type for WAV audio.
    public static let wav: ContentType = "audio/wav"

    /// Content type for PDF files.
    public static let pdf: ContentType = "application/pdf"
}

extension ContentType {

    static var allCases: [ContentType] {
        [
            .json, .xml, .formData, .formURLEncoded,
            .text, .html, .css, .javascript,
            .gif, .png, .jpeg, .bmp, .webp,
            .midi, .mpeg, .wav,
            .pdf
        ]
    }
}

extension ContentType: Equatable {

    public static func == (_ lhs: Self, _ rhs: Self) -> Bool {
        lhs.rawValue == rhs.rawValue
    }
}

extension ContentType: Hashable {

    public func hash(into hasher: inout Hasher) {
        rawValue.hash(into: &hasher)
    }
}

extension ContentType: ExpressibleByStringLiteral {

    /**
     Initializes a `ContentType` instance using a string literal.

     - Parameter value: A string literal representing the media type.
     - Returns: An instance of `ContentType` with the specified media type.

     - Note: Use this initializer to create a `ContentType` instance from a string literal.
     */
    public init(stringLiteral value: StringLiteralType) {
        self.init(value)
    }
}

extension ContentType: CustomStringConvertible {

    public var description: String {
        rawValue
    }
}
