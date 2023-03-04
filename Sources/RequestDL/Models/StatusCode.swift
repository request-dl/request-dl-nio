//
//  File.swift
//
//
//  Created by Brenno on 04/03/23.
//

import Foundation

public struct StatusCode {

    let rawValue: Int

    init(rawValue: Int) {
        self.rawValue = rawValue
    }
}

extension StatusCode {

    public static func custom(_ rawValue: Int) -> StatusCode {
        .init(rawValue: rawValue)
    }
}

extension StatusCode {

    static var `continue`: StatusCode {
        .init(rawValue: 100)
    }

    static var switchingProtocols: StatusCode {
        .init(rawValue: 101)
    }

    static var processing: StatusCode {
        .init(rawValue: 102)
    }
}

extension StatusCode {

    static var ok: StatusCode {
        .init(rawValue: 200)
    }

    static var created: StatusCode {
        .init(rawValue: 201)
    }

    static var accepted: StatusCode {
        .init(rawValue: 202)
    }

    static var nonAuthoritativeInformation: StatusCode {
        .init(rawValue: 203)
    }

    static var noContent: StatusCode {
        .init(rawValue: 204)
    }

    static var resetContent: StatusCode {
        .init(rawValue: 205)
    }

    static var partialContent: StatusCode {
        .init(rawValue: 206)
    }

    static var multiStatus: StatusCode {
        .init(rawValue: 207)
    }

    static var alreadyReported: StatusCode {
        .init(rawValue: 208)
    }

    static var imUsed: StatusCode {
        .init(rawValue: 226)
    }
}

extension StatusCode {

    static var multipleChoices: StatusCode {
        .init(rawValue: 300)
    }

    static var movedPermanently: StatusCode {
        .init(rawValue: 301)
    }

    static var found: StatusCode {
        .init(rawValue: 302)
    }

    static var seeOther: StatusCode {
        .init(rawValue: 303)
    }

    static var notModified: StatusCode {
        .init(rawValue: 304)
    }

    static var useProxy: StatusCode {
        .init(rawValue: 305)
    }

    static var temporaryRedirect: StatusCode {
        .init(rawValue: 307)
    }

    static var permanentRedirect: StatusCode {
        .init(rawValue: 308)
    }
}

extension StatusCode {

    static var badRequest: StatusCode {
        .init(rawValue: 400)
    }

    static var unauthorized: StatusCode {
        .init(rawValue: 401)
    }

    static var paymentRequired: StatusCode {
        .init(rawValue: 402)
    }

    static var forbidden: StatusCode {
        .init(rawValue: 403)
    }

    static var notFound: StatusCode {
        .init(rawValue: 404)
    }

    static var methodNotAllowed: StatusCode {
        .init(rawValue: 405)
    }

    static var notAcceptable: StatusCode {
        .init(rawValue: 406)
    }

    static var proxyAuthenticationRequired: StatusCode {
        .init(rawValue: 407)
    }

    static var requestTimeout: StatusCode {
        .init(rawValue: 408)
    }

    static var conflict: StatusCode {
        .init(rawValue: 409)
    }

    static var gone: StatusCode {
        .init(rawValue: 410)
    }

    static var lengthRequired: StatusCode {
        .init(rawValue: 411)
    }

    static var preconditionFailed: StatusCode {
        .init(rawValue: 412)
    }

    static var payloadTooLarge: StatusCode {
        .init(rawValue: 413)
    }

    static var uriTooLong: StatusCode {
        .init(rawValue: 414)
    }

    static var unsupportedMediaType: StatusCode {
        .init(rawValue: 415)
    }

    static var rangeNotSatisfiable: StatusCode {
        .init(rawValue: 416)
    }

    static var expectationFailed: StatusCode {
        .init(rawValue: 417)
    }

    static var iAmATeapot: StatusCode {
        .init(rawValue: 418)
    }

    static var misdirectedRequest: StatusCode {
        .init(rawValue: 421)
    }

    static var unprocessableEntity: StatusCode {
        .init(rawValue: 422)
    }

    static var locked: StatusCode {
        .init(rawValue: 423)
    }

    static var failedDependency: StatusCode {
        .init(rawValue: 424)
    }

    static var tooEarly: StatusCode {
        .init(rawValue: 425)
    }

    static var upgradeRequired: StatusCode {
        .init(rawValue: 426)
    }

    static var preconditionRequired: StatusCode {
        .init(rawValue: 428)
    }

    static var tooManyRequests: StatusCode {
        .init(rawValue: 429)
    }

    static var requestHeaderFieldsTooLarge: StatusCode {
        .init(rawValue: 431)
    }

    static var unavailableForLegalReasons: StatusCode {
        .init(rawValue: 451)
    }
}

extension StatusCode {

    static var internalServerError: StatusCode {
        .init(rawValue: 500)
    }

    static var notImplemented: StatusCode {
        .init(rawValue: 501)
    }

    static var badGateway: StatusCode {
        .init(rawValue: 502)
    }

    static var serviceUnavailable: StatusCode {
        .init(rawValue: 503)
    }

    static var gatewayTimeout: StatusCode {
        .init(rawValue: 504)
    }

    static var httpVersionNotSupported: StatusCode {
        .init(rawValue: 505)
    }

    static var variantAlsoNegotiates: StatusCode {
        .init(rawValue: 506)
    }

    static var insufficientStorage: StatusCode {
        .init(rawValue: 507)
    }

    static var loopDetected: StatusCode {
        .init(rawValue: 508)
    }

    static var notExtended: StatusCode {
        .init(rawValue: 510)
    }

    static var networkAuthenticationRequired: StatusCode {
        .init(rawValue: 511)
    }
}

extension StatusCode: Hashable {

    public static func == (_ lhs: Self, _ rhs: Self) -> Bool {
        lhs.rawValue == rhs.rawValue
    }

    public func hash(into hasher: inout Hasher) {
        rawValue.hash(into: &hasher)
    }
}
