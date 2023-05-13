/*
 See LICENSE for this package's licensing information.
*/

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
public struct ContentType: Sendable, Hashable {

    // MARK: - Public static properties

    /// Content type for JSON data.
    public static let json: ContentType = "application/json"

    /// Content type for XML data.
    public static let xml: ContentType = "application/xml"

    /// Content type for form data with files.
    public static let formData: ContentType = "form-data"

    /// Content type for form data in the `x-www-form-urlencoded; charset=utf-8` format.
    public static let formURLEncoded: ContentType = "application/x-www-form-urlencoded; charset=utf-8"

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

    // MARK: - Internal properties

    let rawValue: String

    // MARK: - Inits

    /**
     Initializes a `ContentType` instance with a given string value.

     - Parameter rawValue: The string value of the content type.
     */
    public init<S: StringProtocol>(_ rawValue: S) {
        self.rawValue = String(rawValue)
    }

    // MARK: - Internal static methods

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

// MARK: - ExpressibleByStringLiteral

extension ContentType: ExpressibleByStringLiteral {

    /**
     Initializes a `ContentType` instance using a string literal.

     - Parameter value: A string literal representing the media type.
     - Returns: An instance of `ContentType` with the specified media type.

     - Note: Use this initializer to create a `ContentType` instance from a string literal.
     */
    public init(stringLiteral value: StringLiteralType) {
        self.rawValue = value
    }
}

// MARK: - LosslessStringConvertible

extension ContentType: LosslessStringConvertible {

    public var description: String {
        rawValue
    }
}
