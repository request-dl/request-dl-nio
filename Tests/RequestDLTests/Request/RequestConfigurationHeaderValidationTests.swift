//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.UUID
#endif

#if canImport(NIOCore)
import AsyncHTTPClient
#endif

/// A request whose header is not a valid HTTP header is refused the same way, with the same error,
/// whichever executor runs it. `.nio` always refused it (AsyncHTTPClient); `.urlSession` used to
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
        #if canImport(NIOCore)
        #expect(error as? HTTPClientError == HTTPClientError.invalidHeaderFieldNames(["X-A: injected"]))
        #else
        #expect(error != nil)
        #endif
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
        #if canImport(NIOCore)
        #expect(error as? HTTPClientError == HTTPClientError.invalidHeaderFieldValues(["a\u{0000}b"]))
        #else
        #expect(error != nil)
        #endif
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
