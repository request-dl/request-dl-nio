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

/**
 The ContentType struct is used to define the media type of the data in the HTTP request.

 Usage:

 ```swift
 let contentType: ContentType = .json
 ```

 - Note: For a complete list of the available types, please see the corresponding static
 properties.

 - Important: The `.custom` static function should be used to specify a media type not
 included in the predefined static properties.
 */
public struct ContentType {

    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }
}

extension ContentType {

    /// Creates a custom content type with the given raw value.
    ///
    /// - Parameter value: The raw value of the content type.
    public static func custom(_ value: String) -> ContentType {
        .init(rawValue: value)
    }
}

extension ContentType {

    /// Content type for JSON data.
    public static var json: ContentType {
        .init(rawValue: "application/json")
    }

    /// Content type for XML data.
    public static var xml: ContentType {
        .init(rawValue: "application/xml")
    }

    /// Content type for form data with files.
    public static var formData: ContentType {
        .init(rawValue: "form-data")
    }

    /**
     Content type for form data in the `x-www-form-urlencoded` format.

     This type can be sent via URL parameters or in the body, but the correct submission format to
     the API must be verified as per `key1=value1&key2=value2`.

     - Warning: When using `Payload`, use init via String.
     */
    public static var formURLEncoded: ContentType {
        .init(rawValue: "application/x-www-form-urlencoded")
    }

    /// Content type for plain text data.
    public static var text: ContentType {
        .init(rawValue: "text/plain")
    }

    /// Content type for HTML data.
    public static var html: ContentType {
        .init(rawValue: "text/html")
    }

    /// Content type for CSS data.
    public static var css: ContentType {
        .init(rawValue: "text/css")
    }

    /// Content type for JavaScript data.
    public static var javascript: ContentType {
        .init(rawValue: "text/javascript")
    }

    /// Content type for GIF images.
    public static var gif: ContentType {
        .init(rawValue: "image/gif")
    }

    /// Content type for PNG images.
    public static var png: ContentType {
        .init(rawValue: "image/png")
    }

    /// Content type for JPEG images.
    public static var jpeg: ContentType {
        .init(rawValue: "image/jpeg")
    }

    /// Content type for BMP images.
    public static var bmp: ContentType {
        .init(rawValue: "image/bmp")
    }

    /// Content type for WebP images.
    public static var webp: ContentType {
        .init(rawValue: "image/webp")
    }

    /// Content type for MIDI audio.
    public static var midi: ContentType {
        .init(rawValue: "audio/midi")
    }

    /// Content type for MPEG audio.
    public static var mpeg: ContentType {
        .init(rawValue: "audio/mpeg")
    }

    /// Content type for WAV audio.
    public static var wav: ContentType {
        .init(rawValue: "audio/wav")
    }

    /// Content type for PDF files.
    public static var pdf: ContentType {
        .init(rawValue: "application/pdf")
    }
}

extension ContentType {

    /// A collection of all available content types.
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

extension ContentType: Hashable {

    public static func == (_ lhs: Self, _ rhs: Self) -> Bool {
        lhs.rawValue == rhs.rawValue
    }

    public func hash(into hasher: inout Hasher) {
        rawValue.hash(into: &hasher)
    }
}
