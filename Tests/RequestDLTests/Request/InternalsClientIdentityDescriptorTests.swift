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

/// Covers `Internals.ClientIdentityDescriptor` -- what `BackgroundDownloadTask` persists for a
/// client certificate (mTLS), and rebuilds fresh from disk on every challenge, live or after a
/// relaunch alike.
struct InternalsClientIdentityDescriptorTests {

    // MARK: - resolve(from:)

    @Test
    func resolve_whenNoClientIdentityConfigured_returnsNil() async throws {
        // Given
        let secureConnection = Internals.SecureConnection()

        // When / Then
        #expect(try Internals.ClientIdentityDescriptor.resolve(from: secureConnection) == nil)
    }

    @Test
    func resolve_whenFileBackedCertificateAndKeyConfigured_capturesPaths() async throws {
        // Given
        let client = Certificates().client()
        let certificatePath = client.certificateURL.absolutePath(percentEncoded: false)
        let privateKeyPath = client.privateKeyURL.absolutePath(percentEncoded: false)

        var secureConnection = Internals.SecureConnection()
        secureConnection.certificateChain = .file(certificatePath)
        secureConnection.privateKey = .privateKey(.init(privateKeyPath, format: .pem))

        // When
        let descriptor = try #require(try Internals.ClientIdentityDescriptor.resolve(from: secureConnection))

        // Then
        #expect(descriptor.certificateChainFilePath == certificatePath)
        #expect(descriptor.privateKeyFilePath == privateKeyPath)
        #expect(descriptor.privateKeyFormat == .pem)
    }

    @Test
    func resolve_whenCertificateChainIsBytesBacked_throwsNonFileBackedSource() async throws {
        // Given
        let client = Certificates().client()
        let certificateBytes = try [UInt8](Data(contentsOf: client.certificateURL))

        var secureConnection = Internals.SecureConnection()
        secureConnection.certificateChain = .bytes(certificateBytes)
        secureConnection.privateKey = .privateKey(
            .init(client.privateKeyURL.absolutePath(percentEncoded: false), format: .pem)
        )

        // When / Then
        #expect(throws: Internals.ClientIdentityDescriptor.ResolutionError.nonFileBackedSource) {
            try Internals.ClientIdentityDescriptor.resolve(from: secureConnection)
        }
    }

    @Test
    func resolve_whenPrivateKeyIsBytesBacked_throwsNonFileBackedSource() async throws {
        // Given
        let client = Certificates().client()
        let privateKeyBytes = try [UInt8](Data(contentsOf: client.privateKeyURL))

        var secureConnection = Internals.SecureConnection()
        secureConnection.certificateChain = .file(client.certificateURL.absolutePath(percentEncoded: false))
        secureConnection.privateKey = .privateKey(.init(privateKeyBytes, format: .pem))

        // When / Then
        #expect(throws: Internals.ClientIdentityDescriptor.ResolutionError.nonFileBackedSource) {
            try Internals.ClientIdentityDescriptor.resolve(from: secureConnection)
        }
    }

    @Test
    func resolve_whenPrivateKeyIsPasswordProtected_throwsPasswordProtectedPrivateKey() async throws {
        // Given
        let client = Certificates().client(password: true)

        var secureConnection = Internals.SecureConnection()
        secureConnection.certificateChain = .file(client.certificateURL.absolutePath(percentEncoded: false))
        secureConnection.privateKey = .privateKey(
            .init(
                client.privateKeyURL.absolutePath(percentEncoded: false),
                format: .pem,
                password: NIOSSLSecureBytes("password".utf8)
            )
        )

        // When / Then
        #expect(throws: Internals.ClientIdentityDescriptor.ResolutionError.passwordProtectedPrivateKey) {
            try Internals.ClientIdentityDescriptor.resolve(from: secureConnection)
        }
    }

    @Test
    func resolve_whenOnlyCertificateChainConfigured_throwsIncompleteClientIdentity() async throws {
        // Given
        let client = Certificates().client()

        var secureConnection = Internals.SecureConnection()
        secureConnection.certificateChain = .file(client.certificateURL.absolutePath(percentEncoded: false))

        // When / Then
        #expect(throws: Internals.ClientIdentityDescriptor.ResolutionError.incompleteClientIdentity) {
            try Internals.ClientIdentityDescriptor.resolve(from: secureConnection)
        }
    }

    @Test
    func resolve_whenOnlyPrivateKeyConfigured_throwsIncompleteClientIdentity() async throws {
        // Given
        let client = Certificates().client()

        var secureConnection = Internals.SecureConnection()
        secureConnection.privateKey = .privateKey(
            .init(client.privateKeyURL.absolutePath(percentEncoded: false), format: .pem)
        )

        // When / Then
        #expect(throws: Internals.ClientIdentityDescriptor.ResolutionError.incompleteClientIdentity) {
            try Internals.ClientIdentityDescriptor.resolve(from: secureConnection)
        }
    }

    // MARK: - Descriptor round trip

    @Test
    func descriptor_isCodableRoundTrippable() async throws {
        // Given
        let descriptor = Internals.ClientIdentityDescriptor(
            certificateChainFilePath: "/tmp/client.pem",
            privateKeyFilePath: "/tmp/client.key",
            privateKeyFormat: .pem
        )

        // When
        let encoded = try JSONEncoder().encode(descriptor)
        let decoded = try JSONDecoder().decode(Internals.ClientIdentityDescriptor.self, from: encoded)

        // Then
        #expect(decoded == descriptor)
    }

    // MARK: - makeIdentity() -- real handshake, rebuilt identity

    /// The whole point of splitting this type out: an identity rebuilt from nothing but a
    /// `Descriptor` -- just a certificate/key file path on disk, no `Internals.SecureConnection`,
    /// no `Property` tree -- still has to genuinely authenticate against a real server requiring
    /// a client certificate, not just hold the right bytes in memory. Known issue in this bare
    /// SwiftPM test harness specifically (no Keychain Sharing entitlement), same gap
    /// `RequestConfigurationURLSessionClientMTLSTests` already documents at the live-executor
    /// layer -- this proves the same wiring one layer further removed (via a JSON round trip
    /// simulating a relaunch), not a new one.
    @Test
    func rebuiltIdentity_whenPresentedToServerRequiringClientCertificate_completesHandshake() async throws {
        // Given
        let server = Certificates().server()
        let client = Certificates().client()
        let uri = "/" + UUID().uuidString

        let localServer = try await LocalServer(
            LocalServer.Configuration(
                host: "localhost",
                port: 8890,
                option: .client(client)
            )
        )

        let output = "Hello World"
        let response = try LocalServer.ResponseConfiguration(jsonObject: output)
        localServer.cleanup(at: uri)
        localServer.insert(response, at: uri)
        defer { localServer.cleanup(at: uri) }

        var secureConnection = Internals.SecureConnection()
        secureConnection.certificateChain = .file(client.certificateURL.absolutePath(percentEncoded: false))
        secureConnection.privateKey = .privateKey(
            .init(client.privateKeyURL.absolutePath(percentEncoded: false), format: .pem)
        )
        secureConnection.trustRoots = .file(server.certificateURL.absolutePath(percentEncoded: false))

        let clientIdentityDescriptor = try #require(
            try Internals.ClientIdentityDescriptor.resolve(from: secureConnection)
        )
        let serverTrustDescriptor = try Internals.ServerTrustPolicy.resolve(from: secureConnection).descriptor

        // Simulates a relaunch: the only things carried forward are the two `Descriptor`s, JSON
        // round-tripped, exactly like `taskDescription`.
        let rebuiltClientIdentityDescriptor = try JSONDecoder().decode(
            Internals.ClientIdentityDescriptor.self,
            from: JSONEncoder().encode(clientIdentityDescriptor)
        )
        let rebuiltServerTrustPolicy = Internals.ServerTrustPolicy(
            descriptor: try JSONDecoder().decode(
                Internals.ServerTrustPolicy.Descriptor.self,
                from: JSONEncoder().encode(serverTrustDescriptor)
            )
        )

        // Then
        await withKnownIssue(
            "this SwiftPM test harness has no Keychain Sharing entitlement on any platform -- see RequestConfigurationURLSessionClientMTLSTests's type doc comment",
            {
                let (handle, intermediates) = try rebuiltClientIdentityDescriptor.makeIdentity()
                defer { Internals.RawBytesIdentityBuilder.remove(handle) }

                let delegate = ClientCertificateForwardingDelegate(
                    identity: handle.identity,
                    intermediates: intermediates,
                    serverTrustPolicy: rebuiltServerTrustPolicy
                )
                let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)

                var request = URLRequest(url: try #require(URL(string: "https://\(localServer.baseURL)\(uri)")))
                request.httpMethod = "GET"

                let (data, response2) = try await session.data(for: request)

                #expect((response2 as? HTTPURLResponse)?.statusCode == 200)
                let decodedBody = try HTTPResult<String>(data)
                #expect(decodedBody.response == output)
            }
        )
    }
}

/// Answers both halves of an mTLS handshake by hand -- the client-certificate credential directly
/// (this suite already has the identity in hand), and the server-trust half via
/// `Internals.ServerTrustPolicy`, the same hookup `BackgroundDownloads.Session`'s own challenge
/// delegate uses for each.
private final class ClientCertificateForwardingDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {

    private let identity: SecIdentity
    private let intermediates: [SecCertificate]
    private let serverTrustPolicy: Internals.ServerTrustPolicy

    init(identity: SecIdentity, intermediates: [SecCertificate], serverTrustPolicy: Internals.ServerTrustPolicy) {
        self.identity = identity
        self.intermediates = intermediates
        self.serverTrustPolicy = serverTrustPolicy
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodClientCertificate else {
            serverTrustPolicy.handle(challenge: challenge, completionHandler: completionHandler)
            return
        }

        completionHandler(
            .useCredential,
            URLCredential(
                identity: identity,
                certificates: intermediates.isEmpty ? nil : intermediates,
                persistence: .forSession
            )
        )
    }
}

#endif
