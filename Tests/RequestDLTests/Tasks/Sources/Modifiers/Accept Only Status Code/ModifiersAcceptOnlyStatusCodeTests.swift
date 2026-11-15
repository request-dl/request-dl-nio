//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

struct ModifiersStatusCodeTests {

    @Test
    func successStatusCodeSet() async throws {
        // Given
        let statusCodes = StatusCode(0)..<600
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
        #expect(
            received.allSatisfy {
                statusCodeSet.contains($0)
            }
        )

        #expect(
            failures.allSatisfy {
                !statusCodeSet.contains($0) && statusCodes.contains($0)
            }
        )

        #expect(failures.count == statusCodes.count - statusCodeSet.count)
    }

    @Test
    func successAndRedirectStatusCodeSet() async throws {
        // Given
        let statusCodes = StatusCode(0)..<600
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
        #expect(
            received.allSatisfy {
                statusCodeSet.contains($0)
            }
        )

        #expect(
            failures.allSatisfy {
                !statusCodeSet.contains($0) && statusCodes.contains($0)
            }
        )

        #expect(failures.count == statusCodes.count - statusCodeSet.count)
    }

    /// A set that ended up empty (an intersection, a list read from a configuration) accepts
    /// nothing: it used to accept everything, which turned the check off exactly when it had
    /// nothing left to allow.
    @Test(arguments: [200, 404, 500])
    func emptyStatusCodeSet_rejectsEveryStatusCode(_ code: UInt) async throws {
        // Given
        let statusCodeSet = StatusCodeSet.success.intersection(StatusCodeSet([StatusCode(404)]))
        var accepted = false

        // When
        do {
            _ = try await MockedTask(
                status: .init(code: code, reason: "mock"),
                content: { BaseURL("localhost") }
            )
            .collectData()
            .acceptOnlyStatusCode(statusCodeSet)
            .result()
            accepted = true
        } catch is InvalidStatusCodeError<TaskResult<Data>> {
            accepted = false
        }

        // Then
        #expect(statusCodeSet.isEmpty)
        #expect(!accepted)
    }
}

extension ModifiersStatusCodeTests {

    func status(_ statusCode: StatusCode) -> ResponseHead.Status {
        .init(code: statusCode.rawValue, reason: "mock")
    }
}
