/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct ModifiersStatusCodeTests {

    @Test
    func successStatusCodeSet() async throws {
        // Given
        let statusCodes = StatusCode(0) ..< 600
        let statusCodeSet: StatusCodeSet = .success
        var received = [StatusCode]()
        var failures = [StatusCode]()

        // When
        for statusCode in statusCodes {
            do {
                _ = try await MockedTask(
                    status: status(statusCode),
                    content: { BaseURL("localhost") }
                )
                .collectData()
                .acceptOnlyStatusCode(statusCodeSet)
                .result()
                received.append(statusCode)
            } catch is InvalidStatusCodeError<TaskResult<Data>> {
                failures.append(statusCode)
            } catch {
                throw error
            }
        }

        // Then
        #expect(statusCodeSet.count == received.count)
        #expect(received.allSatisfy {
            statusCodeSet.contains($0)
        })

        #expect(failures.allSatisfy {
            !statusCodeSet.contains($0) && statusCodes.contains($0)
        })

        #expect(failures.count == statusCodes.count - statusCodeSet.count)
    }

    @Test
    func successAndRedirectStatusCodeSet() async throws {
        // Given
        let statusCodes = StatusCode(0) ..< 600
        let statusCodeSet: StatusCodeSet = .successAndRedirect
        var received = [StatusCode]()
        var failures = [StatusCode]()

        // When
        for statusCode in statusCodes {
            do {
                _ = try await MockedTask(
                    status: status(statusCode),
                    content: { BaseURL("localhost") }
                )
                .collectData()
                .acceptOnlyStatusCode(statusCodeSet)
                .result()
                received.append(statusCode)
            } catch is InvalidStatusCodeError<TaskResult<Data>> {
                failures.append(statusCode)
            } catch {
                throw error
            }
        }

        // Then
        #expect(statusCodeSet.count == received.count)
        #expect(received.allSatisfy {
            statusCodeSet.contains($0)
        })

        #expect(failures.allSatisfy {
            !statusCodeSet.contains($0) && statusCodes.contains($0)
        })

        #expect(failures.count == statusCodes.count - statusCodeSet.count)
    }
}

extension ModifiersStatusCodeTests {

    func status(_ statusCode: StatusCode) -> ResponseHead.Status {
        .init(code: statusCode.rawValue, reason: "mock")
    }
}
