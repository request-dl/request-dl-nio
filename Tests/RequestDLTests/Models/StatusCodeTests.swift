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

import XCTest
@testable import RequestDL

final class StatusCodeTests: XCTestCase {

    func testContinueRawValue() {
        XCTAssertEqual(StatusCode.`continue`, 100)
    }

    func testWwitchingProtocolsRawValue() {
        XCTAssertEqual(StatusCode.switchingProtocols, 101)
    }

    func testProcessingRawValue() {
        XCTAssertEqual(StatusCode.processing, 102)
    }

    func testOkRawValue() {
        XCTAssertEqual(StatusCode.ok, 200)
    }

    func testCreatedRawValue() {
        XCTAssertEqual(StatusCode.created, 201)
    }

    func testAcceptedRawValue() {
        XCTAssertEqual(StatusCode.accepted, 202)
    }

    func testNonAuthoritativeInformationRawValue() {
        XCTAssertEqual(StatusCode.nonAuthoritativeInformation, 203)
    }

    func testNoContentRawValue() {
        XCTAssertEqual(StatusCode.noContent, 204)
    }

    func testResetContentRawValue() {
        XCTAssertEqual(StatusCode.resetContent, 205)
    }

    func testPartialContentRawValue() {
        XCTAssertEqual(StatusCode.partialContent, 206)
    }

    func testMultiStatusRawValue() {
        XCTAssertEqual(StatusCode.multiStatus, 207)
    }

    func testAlreadyReportedRawValue() {
        XCTAssertEqual(StatusCode.alreadyReported, 208)
    }

    func testImUsedRawValue() {
        XCTAssertEqual(StatusCode.imUsed, 226)
    }

    func testMultipleChoicesRawValue() {
        XCTAssertEqual(StatusCode.multipleChoices, 300)
    }

    func testMovedPermanentlyRawValue() {
        XCTAssertEqual(StatusCode.movedPermanently, 301)
    }

    func testFoundRawValue() {
        XCTAssertEqual(StatusCode.found, 302)
    }

    func testSeeOtherRawValue() {
        XCTAssertEqual(StatusCode.seeOther, 303)
    }

    func testNotModifiedRawValue() {
        XCTAssertEqual(StatusCode.notModified, 304)
    }

    func testUseProxyRawValue() {
        XCTAssertEqual(StatusCode.useProxy, 305)
    }

    func testTemporaryRedirectRawValue() {
        XCTAssertEqual(StatusCode.temporaryRedirect, 307)
    }

    func testPermanentRedirectRawValue() {
        XCTAssertEqual(StatusCode.permanentRedirect, 308)
    }

    func testBadRequestRawValue() {
        XCTAssertEqual(StatusCode.badRequest, 400)
    }

    func testUnauthorizedRawValue() {
        XCTAssertEqual(StatusCode.unauthorized, 401)
    }

    func testPaymentRequiredRawValue() {
        XCTAssertEqual(StatusCode.paymentRequired, 402)
    }

    func testForbiddenRawValue() {
        XCTAssertEqual(StatusCode.forbidden, 403)
    }

    func testNotFoundRawValue() {
        XCTAssertEqual(StatusCode.notFound, 404)
    }

    func testMethodNotAllowedRawValue() {
        XCTAssertEqual(StatusCode.methodNotAllowed, 405)
    }

    func testNotAcceptableRawValue() {
        XCTAssertEqual(StatusCode.notAcceptable, 406)
    }

    func testProxyAuthenticationRequiredRawValue() {
        XCTAssertEqual(StatusCode.proxyAuthenticationRequired, 407)
    }

    func testRequestTimeoutRawValue() {
        XCTAssertEqual(StatusCode.requestTimeout, 408)
    }

    func testConflictRawValue() {
        XCTAssertEqual(StatusCode.conflict, 409)
    }

    func testGoneRawValue() {
        XCTAssertEqual(StatusCode.gone, 410)
    }

    func testLengthRequiredRawValue() {
        XCTAssertEqual(StatusCode.lengthRequired, 411)
    }

    func testPreconditionFailedRawValue() {
        XCTAssertEqual(StatusCode.preconditionFailed, 412)
    }

    func testPayloadTooLargeRawValue() {
        XCTAssertEqual(StatusCode.payloadTooLarge, 413)
    }

    func testUriTooLongRawValue() {
        XCTAssertEqual(StatusCode.uriTooLong, 414)
    }

    func testUnsupportedMediaTypeRawValue() {
        XCTAssertEqual(StatusCode.unsupportedMediaType, 415)
    }

    func testRangeNotSatisfiableRawValue() {
        XCTAssertEqual(StatusCode.rangeNotSatisfiable, 416)
    }

    func testExpectationFailedRawValue() {
        XCTAssertEqual(StatusCode.expectationFailed, 417)
    }

    func testImATeapotRawValue() {
        XCTAssertEqual(StatusCode.imATeapot, 418)
    }

    func testMisdirectedRequestRawValue() {
        XCTAssertEqual(StatusCode.misdirectedRequest, 421)
    }

    func testUnprocessableEntityRawValue() {
        XCTAssertEqual(StatusCode.unprocessableEntity, 422)
    }

    func testLockedRawValue() {
        XCTAssertEqual(StatusCode.locked, 423)
    }

    func testFailedDependencyRawValue() {
        XCTAssertEqual(StatusCode.failedDependency, 424)
    }

    func testTooEarlyRawValue() {
        XCTAssertEqual(StatusCode.tooEarly, 425)
    }

    func testUpgradeRequiredRawValue() {
        XCTAssertEqual(StatusCode.upgradeRequired, 426)
    }

    func testPreconditionRequiredRawValue() {
        XCTAssertEqual(StatusCode.preconditionRequired, 428)
    }

    func testTooManyRequestsRawValue() {
        XCTAssertEqual(StatusCode.tooManyRequests, 429)
    }

    func testRequestHeaderFieldsTooLargeRawValue() {
        XCTAssertEqual(StatusCode.requestHeaderFieldsTooLarge, 431)
    }

    func testUnavailableForLegalReasonsRawValue() {
        XCTAssertEqual(StatusCode.unavailableForLegalReasons, 451)
    }

    func testInternalServerErrorRawValue() {
        XCTAssertEqual(StatusCode.internalServerError, 500)
    }

    func testNotImplementedRawValue() {
        XCTAssertEqual(StatusCode.notImplemented, 501)
    }

    func testBadGatewayRawValue() {
        XCTAssertEqual(StatusCode.badGateway, 502)
    }

    func testServiceUnavailableRawValue() {
        XCTAssertEqual(StatusCode.serviceUnavailable, 503)
    }

    func testGatewayTimeoutRawValue() {
        XCTAssertEqual(StatusCode.gatewayTimeout, 504)
    }

    func testHttpVersionNotSupportedRawValue() {
        XCTAssertEqual(StatusCode.httpVersionNotSupported, 505)
    }

    func testVariantAlsoNegotiatesRawValue() {
        XCTAssertEqual(StatusCode.variantAlsoNegotiates, 506)
    }

    func testInsufficientStorageRawValue() {
        XCTAssertEqual(StatusCode.insufficientStorage, 507)
    }

    func testLoopDetectedRawValue() {
        XCTAssertEqual(StatusCode.loopDetected, 508)
    }

    func testNotExtendedRawValue() {
        XCTAssertEqual(StatusCode.notExtended, 510)
    }

    func testNetworkAuthenticationRequiredRawValue() {
        XCTAssertEqual(StatusCode.networkAuthenticationRequired, 511)
    }
}
