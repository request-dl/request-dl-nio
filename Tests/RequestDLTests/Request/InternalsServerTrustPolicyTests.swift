//
// See LICENSE for this package's licensing information.
//

import NIOSSL
import RequestDLInternals
import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

#if canImport(Darwin)

import Foundation
import Security

/// Covers `Internals.ServerTrustPolicy` -- the server-trust half `Internals.URLSessionIdentityPolicy`
/// now composes rather than duplicates, and the piece `BackgroundDownloadTask` resolves at
/// schedule time and rebuilds again from a persisted ``Internals/ServerTrustPolicy/Descriptor``,
/// simulating what happens after a relaunch with nothing else in memory.
struct InternalsServerTrustPolicyTests {

    // MARK: - resolve(from:)

    @Test
    func resolve_whenTrustRootsConfigured_capturesCertificateAndDefaultsToFullVerification() async throws {
        // Given
        let server = Certificates().server()

        var secureConnection = Internals.SecureConnection()
        secureConnection.trustRoots = .file(server.certificateURL.absolutePath(percentEncoded: false))

        // When
        let descriptor = try Internals.ServerTrustPolicy.resolve(from: secureConnection).descriptor

        // Then
        #expect(descriptor.trustedRootCertificatesDER.count == 1)
        #expect(descriptor.verification == .fullVerification)
    }

    @Test
    func resolve_whenNoTrustRootsConfigured_capturesNoCertificates() async throws {
        // Given
        let secureConnection = Internals.SecureConnection()

        // When
        let descriptor = try Internals.ServerTrustPolicy.resolve(from: secureConnection).descriptor

        // Then
        #expect(descriptor.trustedRootCertificatesDER.isEmpty)
    }

    @Test(
        arguments: [
            (NIOSSL.CertificateVerification.none, Internals.ServerTrustPolicy.Descriptor.Verification.none),
            (.fullVerification, .fullVerification),
            (.noHostnameVerification, .noHostnameVerification),
        ]
    )
    func resolve_capturesConfiguredVerificationMode(
        _ pair: (NIOSSL.CertificateVerification, Internals.ServerTrustPolicy.Descriptor.Verification)
    ) async throws {
        // Given
        var secureConnection = Internals.SecureConnection()
        secureConnection.certificateVerification = pair.0

        // When
        let descriptor = try Internals.ServerTrustPolicy.resolve(from: secureConnection).descriptor

        // Then
        #expect(descriptor.verification == pair.1)
    }

    @Test
    func resolve_whenAdditionalTrustRootsConfigured_appendsToTrustRoots() async throws {
        // Given
        let server = Certificates().server()

        var secureConnection = Internals.SecureConnection()
        secureConnection.trustRoots = .file(server.certificateURL.absolutePath(percentEncoded: false))
        secureConnection.additionalTrustRoots = [
            .file(server.certificateURL.absolutePath(percentEncoded: false))
        ]

        // When
        let descriptor = try Internals.ServerTrustPolicy.resolve(from: secureConnection).descriptor

        // Then
        #expect(descriptor.trustedRootCertificatesDER.count == 2)
    }

    // MARK: - Descriptor round trip

    @Test
    func descriptor_roundTripsThroughInit() async throws {
        // Given
        let server = Certificates().server()

        var secureConnection = Internals.SecureConnection()
        secureConnection.trustRoots = .file(server.certificateURL.absolutePath(percentEncoded: false))
        secureConnection.certificateVerification = .noHostnameVerification

        let original = try Internals.ServerTrustPolicy.resolve(from: secureConnection)

        // When -- exactly what survives a relaunch: the `Descriptor`, JSON round-tripped the same
        // way `BackgroundDownloads.Session` persists it on `taskDescription`, then rebuilt from
        // that alone.
        let encoded = try JSONEncoder().encode(original.descriptor)
        let decoded = try JSONDecoder().decode(Internals.ServerTrustPolicy.Descriptor.self, from: encoded)
        let rebuilt = Internals.ServerTrustPolicy(descriptor: decoded)

        // Then
        #expect(rebuilt.descriptor == original.descriptor)
    }

    // MARK: - handle(challenge:completionHandler:) -- real handshake, rebuilt policy

    /// The whole point of splitting this type out: a policy rebuilt from nothing but a
    /// `Descriptor` -- no `Internals.SecureConnection`, no `Property` tree, exactly what a
    /// `BackgroundDownloadTask` delegate callback has after a relaunch -- still has to genuinely
    /// validate a real server certificate against real trust roots, not just hold the right bytes
    /// in memory.
    @Test
    func rebuiltPolicy_whenTrustRootsConfigured_stillVerifiesRealServerCertificateAgainstThem() async throws {
        // Given
        let server = Certificates().server()
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString
        let output = "Hello World"

        let response = try LocalServer.ResponseConfiguration(jsonObject: output)
        localServer.cleanup(at: uri)
        localServer.insert(response, at: uri)
        defer { localServer.cleanup(at: uri) }

        var secureConnection = Internals.SecureConnection()
        secureConnection.trustRoots = .file(server.certificateURL.absolutePath(percentEncoded: false))
        secureConnection.certificateVerification = .fullVerification

        let descriptor = try Internals.ServerTrustPolicy.resolve(from: secureConnection).descriptor

        // Simulates a relaunch: the only thing carried forward is the `Descriptor` itself, JSON
        // round-tripped, exactly like `taskDescription`.
        let encoded = try JSONEncoder().encode(descriptor)
        let decoded = try JSONDecoder().decode(Internals.ServerTrustPolicy.Descriptor.self, from: encoded)
        let rebuiltPolicy = Internals.ServerTrustPolicy(descriptor: decoded)

        let delegate = ForwardingChallengeDelegate(policy: rebuiltPolicy)
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)

        var request = URLRequest(url: try #require(URL(string: "https://\(localServer.baseURL)\(uri)")))
        request.httpMethod = "GET"

        // When
        let (data, response2) = try await session.data(for: request)

        // Then
        #expect((response2 as? HTTPURLResponse)?.statusCode == 200)
        let decodedBody = try HTTPResult<String>(data)
        #expect(decodedBody.response == output)
    }

    @Test
    func rebuiltPolicy_whenTrustRootsDoNotMatch_rejectsRealServerCertificate() async throws {
        // Given -- the client fixture's own certificate is not the one `LocalServer` presents, so
        // anchoring to it specifically must fail the handshake.
        let unrelatedCertificate = Certificates().client()
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString

        localServer.cleanup(at: uri)
        defer { localServer.cleanup(at: uri) }

        var secureConnection = Internals.SecureConnection()
        secureConnection.trustRoots = .file(unrelatedCertificate.certificateURL.absolutePath(percentEncoded: false))
        secureConnection.certificateVerification = .fullVerification

        let descriptor = try Internals.ServerTrustPolicy.resolve(from: secureConnection).descriptor
        let rebuiltPolicy = Internals.ServerTrustPolicy(descriptor: descriptor)

        let delegate = ForwardingChallengeDelegate(policy: rebuiltPolicy)
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)

        var request = URLRequest(url: try #require(URL(string: "https://\(localServer.baseURL)\(uri)")))
        request.httpMethod = "GET"

        // When / Then
        await #expect(throws: (any Error).self) {
            try await session.data(for: request)
        }
    }
}

/// Forwards a session's server-trust challenge straight to a `ServerTrustPolicy` -- the same
/// hookup `BackgroundDownloads.Session`'s own `urlSession(_:task:didReceive:completionHandler:)`
/// does, minus the `taskDescription` decoding step, since this suite already has the policy in
/// hand directly.
private final class ForwardingChallengeDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {

    private let policy: Internals.ServerTrustPolicy

    init(policy: Internals.ServerTrustPolicy) {
        self.policy = policy
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        policy.handle(challenge: challenge, completionHandler: completionHandler)
    }
}

#endif
