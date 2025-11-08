/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct StatusCodeTests {

    @Test
    func continueRawValue() async throws {
        #expect(StatusCode.`continue` == 100)
    }

    @Test
    func wwitchingProtocolsRawValue() async throws {
        #expect(StatusCode.switchingProtocols == 101)
    }

    @Test
    func processingRawValue() async throws {
        #expect(StatusCode.processing == 102)
    }

    @Test
    func okRawValue() async throws {
        #expect(StatusCode.ok == 200)
    }

    @Test
    func createdRawValue() async throws {
        #expect(StatusCode.created == 201)
    }

    @Test
    func acceptedRawValue() async throws {
        #expect(StatusCode.accepted == 202)
    }

    @Test
    func nonAuthoritativeInformationRawValue() async throws {
        #expect(StatusCode.nonAuthoritativeInformation == 203)
    }

    @Test
    func noContentRawValue() async throws {
        #expect(StatusCode.noContent == 204)
    }

    @Test
    func resetContentRawValue() async throws {
        #expect(StatusCode.resetContent == 205)
    }

    @Test
    func partialContentRawValue() async throws {
        #expect(StatusCode.partialContent == 206)
    }

    @Test
    func multiStatusRawValue() async throws {
        #expect(StatusCode.multiStatus == 207)
    }

    @Test
    func alreadyReportedRawValue() async throws {
        #expect(StatusCode.alreadyReported == 208)
    }

    @Test
    func imUsedRawValue() async throws {
        #expect(StatusCode.imUsed == 226)
    }

    @Test
    func multipleChoicesRawValue() async throws {
        #expect(StatusCode.multipleChoices == 300)
    }

    @Test
    func movedPermanentlyRawValue() async throws {
        #expect(StatusCode.movedPermanently == 301)
    }

    @Test
    func foundRawValue() async throws {
        #expect(StatusCode.found == 302)
    }

    @Test
    func seeOtherRawValue() async throws {
        #expect(StatusCode.seeOther == 303)
    }

    @Test
    func notModifiedRawValue() async throws {
        #expect(StatusCode.notModified == 304)
    }

    @Test
    func useProxyRawValue() async throws {
        #expect(StatusCode.useProxy == 305)
    }

    @Test
    func temporaryRedirectRawValue() async throws {
        #expect(StatusCode.temporaryRedirect == 307)
    }

    @Test
    func permanentRedirectRawValue() async throws {
        #expect(StatusCode.permanentRedirect == 308)
    }

    @Test
    func badRequestRawValue() async throws {
        #expect(StatusCode.badRequest == 400)
    }

    @Test
    func unauthorizedRawValue() async throws {
        #expect(StatusCode.unauthorized == 401)
    }

    @Test
    func paymentRequiredRawValue() async throws {
        #expect(StatusCode.paymentRequired == 402)
    }

    @Test
    func forbiddenRawValue() async throws {
        #expect(StatusCode.forbidden == 403)
    }

    @Test
    func notFoundRawValue() async throws {
        #expect(StatusCode.notFound == 404)
    }

    @Test
    func methodNotAllowedRawValue() async throws {
        #expect(StatusCode.methodNotAllowed == 405)
    }

    @Test
    func notAcceptableRawValue() async throws {
        #expect(StatusCode.notAcceptable == 406)
    }

    @Test
    func proxyAuthenticationRequiredRawValue() async throws {
        #expect(StatusCode.proxyAuthenticationRequired == 407)
    }

    @Test
    func requestTimeoutRawValue() async throws {
        #expect(StatusCode.requestTimeout == 408)
    }

    @Test
    func conflictRawValue() async throws {
        #expect(StatusCode.conflict == 409)
    }

    @Test
    func goneRawValue() async throws {
        #expect(StatusCode.gone == 410)
    }

    @Test
    func lengthRequiredRawValue() async throws {
        #expect(StatusCode.lengthRequired == 411)
    }

    @Test
    func preconditionFailedRawValue() async throws {
        #expect(StatusCode.preconditionFailed == 412)
    }

    @Test
    func payloadTooLargeRawValue() async throws {
        #expect(StatusCode.payloadTooLarge == 413)
    }

    @Test
    func uriTooLongRawValue() async throws {
        #expect(StatusCode.uriTooLong == 414)
    }

    @Test
    func unsupportedMediaTypeRawValue() async throws {
        #expect(StatusCode.unsupportedMediaType == 415)
    }

    @Test
    func rangeNotSatisfiableRawValue() async throws {
        #expect(StatusCode.rangeNotSatisfiable == 416)
    }

    @Test
    func expectationFailedRawValue() async throws {
        #expect(StatusCode.expectationFailed == 417)
    }

    @Test
    func imATeapotRawValue() async throws {
        #expect(StatusCode.imATeapot == 418)
    }

    @Test
    func misdirectedRequestRawValue() async throws {
        #expect(StatusCode.misdirectedRequest == 421)
    }

    @Test
    func unprocessableEntityRawValue() async throws {
        #expect(StatusCode.unprocessableEntity == 422)
    }

    @Test
    func lockedRawValue() async throws {
        #expect(StatusCode.locked == 423)
    }

    @Test
    func failedDependencyRawValue() async throws {
        #expect(StatusCode.failedDependency == 424)
    }

    @Test
    func tooEarlyRawValue() async throws {
        #expect(StatusCode.tooEarly == 425)
    }

    @Test
    func upgradeRequiredRawValue() async throws {
        #expect(StatusCode.upgradeRequired == 426)
    }

    @Test
    func preconditionRequiredRawValue() async throws {
        #expect(StatusCode.preconditionRequired == 428)
    }

    @Test
    func tooManyRequestsRawValue() async throws {
        #expect(StatusCode.tooManyRequests == 429)
    }

    @Test
    func requestHeaderFieldsTooLargeRawValue() async throws {
        #expect(StatusCode.requestHeaderFieldsTooLarge == 431)
    }

    @Test
    func unavailableForLegalReasonsRawValue() async throws {
        #expect(StatusCode.unavailableForLegalReasons == 451)
    }

    @Test
    func internalServerErrorRawValue() async throws {
        #expect(StatusCode.internalServerError == 500)
    }

    @Test
    func notImplementedRawValue() async throws {
        #expect(StatusCode.notImplemented == 501)
    }

    @Test
    func badGatewayRawValue() async throws {
        #expect(StatusCode.badGateway == 502)
    }

    @Test
    func serviceUnavailableRawValue() async throws {
        #expect(StatusCode.serviceUnavailable == 503)
    }

    @Test
    func gatewayTimeoutRawValue() async throws {
        #expect(StatusCode.gatewayTimeout == 504)
    }

    @Test
    func httpVersionNotSupportedRawValue() async throws {
        #expect(StatusCode.httpVersionNotSupported == 505)
    }

    @Test
    func variantAlsoNegotiatesRawValue() async throws {
        #expect(StatusCode.variantAlsoNegotiates == 506)
    }

    @Test
    func insufficientStorageRawValue() async throws {
        #expect(StatusCode.insufficientStorage == 507)
    }

    @Test
    func loopDetectedRawValue() async throws {
        #expect(StatusCode.loopDetected == 508)
    }

    @Test
    func notExtendedRawValue() async throws {
        #expect(StatusCode.notExtended == 510)
    }

    @Test
    func networkAuthenticationRequiredRawValue() async throws {
        #expect(StatusCode.networkAuthenticationRequired == 511)
    }

    @Test
    func statusCode_withStringLossless() async throws {
        // Given
        let statusCode = StatusCode.ok

        // When
        let string = String(statusCode)
        let losslessStatusCode = StatusCode(string)

        // Then
        #expect(string == statusCode.description)
        #expect(losslessStatusCode == statusCode)
    }
}
