//
//  StatusCodeTests.swift
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
 The HTTP status code for a response.

 Usage:

 ```swift
 let statusCode: StatusCode = .continue
 ```

 - Note: For a complete list of the available status codes, please see the corresponding static
 properties.

 - Important: If the status code is not included in the predefined static properties, use
 a integer literal to initialize an instance of StatusCode.

 The StatusCode struct conforms to the `ExpressibleByIntegerLiteral` protocol, allowing
 it to be initialized with a integer literal, like so:

 ```swift
 let customStatusCode: StatusCode = 99
 ```
*/
public struct StatusCode {

    let rawValue: Int

    /// Initializes a status code with the provided integer value.
    ///
    /// - Parameter rawValue: The integer value of the status code.
    public init(_ rawValue: Int) {
        self.rawValue = rawValue
    }
}

extension StatusCode {

    /// The 101 Switching Continue status code.
    public static let `continue`: StatusCode = 100

    /// The 101 Switching Protocols status code.
    public static let switchingProtocols: StatusCode = 101

    /// The 102 Processing status code.
    public static let processing: StatusCode = 102
}

extension StatusCode {

    /// The 200 OK status code.
    public static let ok: StatusCode = 200

    /// The 201 Created status code.
    public static let created: StatusCode = 201

    /// The 202 Accepted status code.
    public static let accepted: StatusCode = 202

    /// The 203 Non-Authoritative Information status code.
    public static let nonAuthoritativeInformation: StatusCode = 203

    /// The 204 No Content status code.
    public static let noContent: StatusCode = 204

    /// The 205 Reset Content status code.
    public static let resetContent: StatusCode = 205

    /// The 206 Partial Content status code.
    public static let partialContent: StatusCode = 206

    /// The 207 Multi-Status status code.
    public static let multiStatus: StatusCode = 207

    /// The 208 Already Reported status code.
    public static let alreadyReported: StatusCode = 208

    /// The 226 IM Used status code.
    public static let imUsed: StatusCode = 226
}

extension StatusCode {

    /// The 300 Multiple Choices status code.
    public static let multipleChoices: StatusCode = 300

    /// The 301 Moved Permanently status code.
    public static let movedPermanently: StatusCode = 301

    /// The 302 Found status code.
    public static let found: StatusCode = 302

    /// The 303 See Other status code.
    public static let seeOther: StatusCode = 303

    /// The 304 Not Modified status code.
    public static let notModified: StatusCode = 304

    /// The 305 Use Proxy status code.
    public static let useProxy: StatusCode = 305

    /// The 307 Temporary Redirect status code.
    public static let temporaryRedirect: StatusCode = 307

    /// The 308 Permanent Redirect status code.
    public static let permanentRedirect: StatusCode = 308
}

extension StatusCode {

    /// The 400 Bad Request status code.
    public static let badRequest: StatusCode = 400

    /// The 401 Unauthorized status code.
    public static let unauthorized: StatusCode = 401

    /// The 402 Payment Required status code.
    public static let paymentRequired: StatusCode = 402

    /// The 403 Forbidden status code.
    public static let forbidden: StatusCode = 403

    /// The 404 Not Found status code.
    public static let notFound: StatusCode = 404

    /// The 405 Method Not Allowed status code.
    public static let methodNotAllowed: StatusCode = 405

    /// The 406 Not Acceptable status code.
    public static let notAcceptable: StatusCode = 406

    /// The 407 Proxy Authentication Required status code.
    public static let proxyAuthenticationRequired: StatusCode = 407

    /// The 408 Request Timeout status code.
    public static let requestTimeout: StatusCode = 408

    /// The 409 Conflict status code.
    public static let conflict: StatusCode = 409

    /// The 410 Gone status code.
    public static let gone: StatusCode = 410

    /// The 411 Length Required status code.
    public static let lengthRequired: StatusCode = 411

    /// The 412 Precondition Failed status code.
    public static let preconditionFailed: StatusCode = 412

    /// The 413 Payload Too Large status code.
    public static let payloadTooLarge: StatusCode = 413

    /// The 414 URI Too Long status code.
    public static let uriTooLong: StatusCode = 414

    /// The 415 Unsupported Media Type status code.
    public static let unsupportedMediaType: StatusCode = 415

    /// The 416 Range Not Satisfiable status code.
    public static let rangeNotSatisfiable: StatusCode = 416

    /// The 417 Expectation Failed status code.
    public static let expectationFailed: StatusCode = 417

    /// The 418 IM A Teapot status code.
    public static let imATeapot: StatusCode = 418

    /// The 421 Misdirected Request status code.
    public static let misdirectedRequest: StatusCode = 421

    /// The 422 Unprocessable Entity status code.
    public static let unprocessableEntity: StatusCode = 422

    /// The 423 Locked status code.
    public static let locked: StatusCode = 423

    /// The 424 Failed Dependency status code.
    public static let failedDependency: StatusCode = 424

    /// The 425 Too Early status code.
    public static let tooEarly: StatusCode = 425

    /// The 426 Upgrade Required status code.
    public static let upgradeRequired: StatusCode = 426

    /// The 428 Precondition Required status code.
    public static let preconditionRequired: StatusCode = 428

    /// The 429 Too Many Requests status code.
    public static let tooManyRequests: StatusCode = 429

    /// The 431 Request Header Fields Too Large status code.
    public static let requestHeaderFieldsTooLarge: StatusCode = 431

    /// The 451 Unavailable For Legal Reasons status code.
    public static let unavailableForLegalReasons: StatusCode = 451
}

extension StatusCode {

    /// The 500 Internal Server Error status code.
    public static let internalServerError: StatusCode = 500

    /// The 501 Not Implemented status code.
    public static let notImplemented: StatusCode = 501

    /// The 502 Bad Gateway status code.
    public static let badGateway: StatusCode = 502

    /// The 503 Service Unavailable status code.
    public static let serviceUnavailable: StatusCode = 503

    /// The 504 Gateway Timeout status code.
    public static let gatewayTimeout: StatusCode = 504

    /// The 505 HTTP Version Not Supported status code.
    public static let httpVersionNotSupported: StatusCode = 505

    /// The 506 Variant Also Negotiates status code.
    public static let variantAlsoNegotiates: StatusCode = 506

    /// The 507 Insufficient Storage status code.
    public static let insufficientStorage: StatusCode = 507

    /// The 508 Loop Detected status code.
    public static let loopDetected: StatusCode = 508

    /// The 510 Not Extended status code.
    public static let notExtended: StatusCode = 510

    /// The 511 Network Authentication Required status code.
    public static let networkAuthenticationRequired: StatusCode = 511
}

extension StatusCode: Hashable {

    public static func == (_ lhs: Self, _ rhs: Self) -> Bool {
        lhs.rawValue == rhs.rawValue
    }

    public func hash(into hasher: inout Hasher) {
        rawValue.hash(into: &hasher)
    }
}

extension StatusCode: ExpressibleByIntegerLiteral {

    /// Creates a new `StatusCode` instance with the specified integer literal value.
    ///
    /// - Parameter value: The integer literal value.
    public init(integerLiteral value: IntegerLiteralType) {
        self.init(value)
    }
}

extension StatusCode: Comparable {

    public static func < (_ lhs: StatusCode, _ rhs: StatusCode) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
