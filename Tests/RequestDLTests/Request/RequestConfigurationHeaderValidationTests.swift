//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals
import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.UUID
#endif

/// A request whose header is not a valid HTTP header is refused the same way, with the same error,
/// whichever executor runs it, and the error never carries a header value (it can be a token). `.nio` always refused it (AsyncHTTPClient); `.urlSession` used to
/// send it: a name of `X-A: injected` reached the server as `X-A: injected: v`, a value with a NUL
/// as a NUL.
struct RequestConfigurationHeaderValidationTests {

    // MARK: - Inner types

    enum Executor: String, Sendable, CustomTestStringConvertible {
        #if canImport(Darwin)
        case urlSession
        #endif
        #if canImport(NIOCore)
        case nio
        #endif

        var testDescription: String { rawValue }

        func apply(to session: Session) -> Session {
            switch self {
            #if canImport(Darwin)
            case .urlSession:
                return session.requiredExecutor(.urlSession)
            #endif
            #if canImport(NIOCore)
            case .nio:
                return session.requiredExecutor(.nio)
            #endif
            }
        }
    }

    static let executors: [Executor] = {
        var executors = [Executor]()
        #if canImport(Darwin)
        executors.append(.urlSession)
        #endif
        #if canImport(NIOCore)
        executors.append(.nio)
        #endif
        return executors
    }()

    // MARK: - Tests

    @Test(arguments: executors)
    func dataTask_whenHeaderNameIsNotAToken_failsBeforeReachingTheServer(executor: Executor) async throws {
        // Given
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString

        localServer.cleanup(at: uri)
        localServer.insert(try LocalServer.ResponseConfiguration(jsonObject: "reached"), at: uri)
        defer { localServer.cleanup(at: uri) }

        // When
        let error = await #expect(throws: (any Error).self) {
            _ = try await DataTask {
                BaseURL(localServer.baseURL)
                Path(uri)
                CustomHeader(name: "X-A: injected", value: "v")

                executor.apply(to: .localServer)

                SecureConnection {
                    TrustRoots(Certificates().server().certificateURL.absolutePath(percentEncoded: false))
                }
            }
            .extractPayload()
            .result()
        }

        // Then
        #expect(error as? Internals.InvalidHeaderError == Internals.InvalidHeaderError(.name, count: 1))
    }

    @Test(arguments: executors)
    func dataTask_whenHeaderValueHasANUL_failsBeforeReachingTheServer(executor: Executor) async throws {
        // Given
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString

        localServer.cleanup(at: uri)
        localServer.insert(try LocalServer.ResponseConfiguration(jsonObject: "reached"), at: uri)
        defer { localServer.cleanup(at: uri) }

        // When
        let error = await #expect(throws: (any Error).self) {
            _ = try await DataTask {
                BaseURL(localServer.baseURL)
                Path(uri)
                CustomHeader(name: "X-A", value: "a\u{0000}b")

                executor.apply(to: .localServer)

                SecureConnection {
                    TrustRoots(Certificates().server().certificateURL.absolutePath(percentEncoded: false))
                }
            }
            .extractPayload()
            .result()
        }

        // Then
        #expect(
            error as? Internals.InvalidHeaderError
                == Internals.InvalidHeaderError(.value, count: 1, headerNames: ["X-A"])
        )
    }

    /// A token read from a file or the environment with a stray control character is a likely way to
    /// get here, and the error goes to logs.
    @Test(arguments: executors)
    func dataTask_whenAnAuthorizationValueIsRejected_theErrorDoesNotCarryIt(executor: Executor) async throws {
        // Given
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString

        localServer.cleanup(at: uri)
        localServer.insert(try LocalServer.ResponseConfiguration(jsonObject: "reached"), at: uri)
        defer { localServer.cleanup(at: uri) }

        // When
        let error = await #expect(throws: (any Error).self) {
            _ = try await DataTask {
                BaseURL(localServer.baseURL)
                Path(uri)
                CustomHeader(name: "Authorization", value: "Bearer s3cr3t\u{0000}token")

                executor.apply(to: .localServer)

                SecureConnection {
                    TrustRoots(Certificates().server().certificateURL.absolutePath(percentEncoded: false))
                }
            }
            .extractPayload()
            .result()
        }

        // Then
        let error_ = try #require(error)

        for text in [String(describing: error_), String(reflecting: error_), "\(error_)"] {
            #expect(!text.contains("s3cr3t"))
        }
    }

    /// The control: a non-ASCII value is sent on both, so refusing the two cases above did not
    /// narrow what a request may carry.
    @Test(arguments: executors)
    func dataTask_whenHeaderValueIsNonASCII_isSent(executor: Executor) async throws {
        // Given
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString

        localServer.cleanup(at: uri)
        localServer.insert(try LocalServer.ResponseConfiguration(jsonObject: "reached"), at: uri)
        defer { localServer.cleanup(at: uri) }

        // When
        let data = try await DataTask {
            BaseURL(localServer.baseURL)
            Path(uri)
            CustomHeader(name: "X-A", value: "José")

            executor.apply(to: .localServer)

            SecureConnection {
                TrustRoots(Certificates().server().certificateURL.absolutePath(percentEncoded: false))
            }
        }
        .extractPayload()
        .result()

        // Then
        #expect(try HTTPResult<String>(data).response == "reached")
    }
}
