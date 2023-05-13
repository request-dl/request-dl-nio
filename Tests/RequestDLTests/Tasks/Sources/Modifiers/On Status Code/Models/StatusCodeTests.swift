/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

@RequestActor
class StatusCodeTests: XCTestCase {

    func testContinueRawValue() async throws {
        XCTAssertEqual(StatusCode.`continue`, 100)
    }

    func testWwitchingProtocolsRawValue() async throws {
        XCTAssertEqual(StatusCode.switchingProtocols, 101)
    }

    func testProcessingRawValue() async throws {
        XCTAssertEqual(StatusCode.processing, 102)
    }

    func testOkRawValue() async throws {
        XCTAssertEqual(StatusCode.ok, 200)
    }

    func testCreatedRawValue() async throws {
        XCTAssertEqual(StatusCode.created, 201)
    }

    func testAcceptedRawValue() async throws {
        XCTAssertEqual(StatusCode.accepted, 202)
    }

    func testNonAuthoritativeInformationRawValue() async throws {
        XCTAssertEqual(StatusCode.nonAuthoritativeInformation, 203)
    }

    func testNoContentRawValue() async throws {
        XCTAssertEqual(StatusCode.noContent, 204)
    }

    func testResetContentRawValue() async throws {
        XCTAssertEqual(StatusCode.resetContent, 205)
    }

    func testPartialContentRawValue() async throws {
        XCTAssertEqual(StatusCode.partialContent, 206)
    }

    func testMultiStatusRawValue() async throws {
        XCTAssertEqual(StatusCode.multiStatus, 207)
    }

    func testAlreadyReportedRawValue() async throws {
        XCTAssertEqual(StatusCode.alreadyReported, 208)
    }

    func testImUsedRawValue() async throws {
        XCTAssertEqual(StatusCode.imUsed, 226)
    }

    func testMultipleChoicesRawValue() async throws {
        XCTAssertEqual(StatusCode.multipleChoices, 300)
    }

    func testMovedPermanentlyRawValue() async throws {
        XCTAssertEqual(StatusCode.movedPermanently, 301)
    }

    func testFoundRawValue() async throws {
        XCTAssertEqual(StatusCode.found, 302)
    }

    func testSeeOtherRawValue() async throws {
        XCTAssertEqual(StatusCode.seeOther, 303)
    }

    func testNotModifiedRawValue() async throws {
        XCTAssertEqual(StatusCode.notModified, 304)
    }

    func testUseProxyRawValue() async throws {
        XCTAssertEqual(StatusCode.useProxy, 305)
    }

    func testTemporaryRedirectRawValue() async throws {
        XCTAssertEqual(StatusCode.temporaryRedirect, 307)
    }

    func testPermanentRedirectRawValue() async throws {
        XCTAssertEqual(StatusCode.permanentRedirect, 308)
    }

    func testBadRequestRawValue() async throws {
        XCTAssertEqual(StatusCode.badRequest, 400)
    }

    func testUnauthorizedRawValue() async throws {
        XCTAssertEqual(StatusCode.unauthorized, 401)
    }

    func testPaymentRequiredRawValue() async throws {
        XCTAssertEqual(StatusCode.paymentRequired, 402)
    }

    func testForbiddenRawValue() async throws {
        XCTAssertEqual(StatusCode.forbidden, 403)
    }

    func testNotFoundRawValue() async throws {
        XCTAssertEqual(StatusCode.notFound, 404)
    }

    func testMethodNotAllowedRawValue() async throws {
        XCTAssertEqual(StatusCode.methodNotAllowed, 405)
    }

    func testNotAcceptableRawValue() async throws {
        XCTAssertEqual(StatusCode.notAcceptable, 406)
    }

    func testProxyAuthenticationRequiredRawValue() async throws {
        XCTAssertEqual(StatusCode.proxyAuthenticationRequired, 407)
    }

    func testRequestTimeoutRawValue() async throws {
        XCTAssertEqual(StatusCode.requestTimeout, 408)
    }

    func testConflictRawValue() async throws {
        XCTAssertEqual(StatusCode.conflict, 409)
    }

    func testGoneRawValue() async throws {
        XCTAssertEqual(StatusCode.gone, 410)
    }

    func testLengthRequiredRawValue() async throws {
        XCTAssertEqual(StatusCode.lengthRequired, 411)
    }

    func testPreconditionFailedRawValue() async throws {
        XCTAssertEqual(StatusCode.preconditionFailed, 412)
    }

    func testPayloadTooLargeRawValue() async throws {
        XCTAssertEqual(StatusCode.payloadTooLarge, 413)
    }

    func testUriTooLongRawValue() async throws {
        XCTAssertEqual(StatusCode.uriTooLong, 414)
    }

    func testUnsupportedMediaTypeRawValue() async throws {
        XCTAssertEqual(StatusCode.unsupportedMediaType, 415)
    }

    func testRangeNotSatisfiableRawValue() async throws {
        XCTAssertEqual(StatusCode.rangeNotSatisfiable, 416)
    }

    func testExpectationFailedRawValue() async throws {
        XCTAssertEqual(StatusCode.expectationFailed, 417)
    }

    func testImATeapotRawValue() async throws {
        XCTAssertEqual(StatusCode.imATeapot, 418)
    }

    func testMisdirectedRequestRawValue() async throws {
        XCTAssertEqual(StatusCode.misdirectedRequest, 421)
    }

    func testUnprocessableEntityRawValue() async throws {
        XCTAssertEqual(StatusCode.unprocessableEntity, 422)
    }

    func testLockedRawValue() async throws {
        XCTAssertEqual(StatusCode.locked, 423)
    }

    func testFailedDependencyRawValue() async throws {
        XCTAssertEqual(StatusCode.failedDependency, 424)
    }

    func testTooEarlyRawValue() async throws {
        XCTAssertEqual(StatusCode.tooEarly, 425)
    }

    func testUpgradeRequiredRawValue() async throws {
        XCTAssertEqual(StatusCode.upgradeRequired, 426)
    }

    func testPreconditionRequiredRawValue() async throws {
        XCTAssertEqual(StatusCode.preconditionRequired, 428)
    }

    func testTooManyRequestsRawValue() async throws {
        XCTAssertEqual(StatusCode.tooManyRequests, 429)
    }

    func testRequestHeaderFieldsTooLargeRawValue() async throws {
        XCTAssertEqual(StatusCode.requestHeaderFieldsTooLarge, 431)
    }

    func testUnavailableForLegalReasonsRawValue() async throws {
        XCTAssertEqual(StatusCode.unavailableForLegalReasons, 451)
    }

    func testInternalServerErrorRawValue() async throws {
        XCTAssertEqual(StatusCode.internalServerError, 500)
    }

    func testNotImplementedRawValue() async throws {
        XCTAssertEqual(StatusCode.notImplemented, 501)
    }

    func testBadGatewayRawValue() async throws {
        XCTAssertEqual(StatusCode.badGateway, 502)
    }

    func testServiceUnavailableRawValue() async throws {
        XCTAssertEqual(StatusCode.serviceUnavailable, 503)
    }

    func testGatewayTimeoutRawValue() async throws {
        XCTAssertEqual(StatusCode.gatewayTimeout, 504)
    }

    func testHttpVersionNotSupportedRawValue() async throws {
        XCTAssertEqual(StatusCode.httpVersionNotSupported, 505)
    }

    func testVariantAlsoNegotiatesRawValue() async throws {
        XCTAssertEqual(StatusCode.variantAlsoNegotiates, 506)
    }

    func testInsufficientStorageRawValue() async throws {
        XCTAssertEqual(StatusCode.insufficientStorage, 507)
    }

    func testLoopDetectedRawValue() async throws {
        XCTAssertEqual(StatusCode.loopDetected, 508)
    }

    func testNotExtendedRawValue() async throws {
        XCTAssertEqual(StatusCode.notExtended, 510)
    }

    func testNetworkAuthenticationRequiredRawValue() async throws {
        XCTAssertEqual(StatusCode.networkAuthenticationRequired, 511)
    }

    func testStatusCode_withStringLossless() async throws {
        // Given
        let statusCode = StatusCode.ok

        // When
        let string = String(statusCode)
        let losslessStatusCode = StatusCode(string)

        // Then
        XCTAssertEqual(string, statusCode.description)
        XCTAssertEqual(losslessStatusCode, statusCode)
    }
}
