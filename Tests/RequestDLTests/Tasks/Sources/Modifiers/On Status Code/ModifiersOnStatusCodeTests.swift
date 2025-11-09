/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct ModifiersOnStatusCodeTests {

    struct AnyError: Error {}

    @Test
    func statusCode() async throws {
        // Given
        let statusCode: StatusCode = .ok
        var throwAnyError = false

        // When
        do {
            _ = try await MockedTask(
                status: status(statusCode),
                content: {
                    BaseURL("localhost")
                }
            )
            .collectData()
            .onStatusCode(statusCode) { _ in
                throw AnyError()
            }
            .result()
        } catch is AnyError {
            throwAnyError = true
        } catch { throw error }

        // Then
        #expect(throwAnyError)
    }

    @Test
    func statusCodeRange() async throws {
        // Given
        let statusCodes = StatusCode.ok ..< .badRequest
        var received = [StatusCode]()

        // When
        for statusCode in StatusCode.continue ... .networkAuthenticationRequired {
            do {
                _ = try await MockedTask(
                    status: status(statusCode),
                    content: {
                        BaseURL("localhost")
                    }
                )
                .collectData()
                .onStatusCode(statusCodes) { _ in
                    throw AnyError()
                }
                .result()
            } catch is AnyError {
                received.append(statusCode)
            } catch { throw error }
        }

        // Then
        #expect(statusCodes.count == received.count)
        #expect(received.allSatisfy {
            statusCodes.contains($0)
        })
    }

    @Test
    func successStatusCodeSet() async throws {
        // Given
        let statusCodeSet: StatusCodeSet = .success
        var received = [StatusCode]()

        // When
        for statusCode in StatusCode.continue ... .networkAuthenticationRequired {
            do {
                _ = try await MockedTask(
                    status: status(statusCode),
                    content: {
                        BaseURL("localhost")
                    }
                )
                .collectData()
                .onStatusCode(statusCodeSet) { _ in
                    throw AnyError()
                }
                .result()
            } catch is AnyError {
                received.append(statusCode)
            } catch { throw error }
        }

        // Then
        #expect(statusCodeSet.count == received.count)
        #expect(received.allSatisfy {
            statusCodeSet.contains($0)
        })
    }

    @Test
    func successAndRedirectStatusCodeSet() async throws {
        // Given
        let statusCodeSet: StatusCodeSet = .successAndRedirect
        var received = [StatusCode]()

        // When
        for statusCode in StatusCode.continue ... .networkAuthenticationRequired {
            do {
                _ = try await MockedTask(
                    status: status(statusCode),
                    content: {
                        BaseURL("localhost")
                    }
                )
                .collectData()
                .onStatusCode(statusCodeSet) { _ in
                    throw AnyError()
                }
                .result()
            } catch is AnyError {
                received.append(statusCode)
            } catch { throw error }
        }

        // Then
        #expect(statusCodeSet.count == received.count)
        #expect(received.allSatisfy {
            statusCodeSet.contains($0)
        })
    }
}

extension ModifiersOnStatusCodeTests {

    func status(_ statusCode: StatusCode) -> ResponseHead.Status {
        .init(code: statusCode.rawValue, reason: "Mocked")
    }
}
