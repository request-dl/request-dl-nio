//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals
import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

#if canImport(Darwin)

import Foundation
import Security

/// Covers `Internals.ClientIdentityDescriptor`: what `BackgroundDownloadTask` persists for a
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
                password: SecureBytes("password".utf8)
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

    // MARK: - makeIdentity() (real handshake, rebuilt identity)

    /// The whole point of splitting this type out: an identity rebuilt from nothing but a
    /// `Descriptor` (just a certificate/key file path on disk, no `Internals.SecureConnection`,
    /// no `Property` tree) still has to genuinely authenticate against a real server requiring
    /// a client certificate, not just hold the right bytes in memory.
    ///
    /// The Keychain round trip this needs genuinely succeeds on real macOS (bare `swift test` or
    /// an Xcode-run macOS test bundle) once `Internals.RawBytesIdentityBuilder.makeIdentity(_:_:)`
    /// sets `kSecAttrApplicationLabel` correctly -- confirmed, not assumed, and no longer a known
    /// issue there. Every other Apple platform's Simulator, reached only via `xcodebuild test`
    /// against SwiftPM's auto-generated scheme, has no `.entitlements` file to add Keychain
    /// Sharing to at all, so `SecItemAdd` there fails with `errSecMissingEntitlement` before
    /// identity pairing is ever reached -- a genuinely different, still-open gap, confirmed
    /// directly on iOS/tvOS/watchOS Simulator CI runs.
    @Test
    func rebuiltIdentity_whenPresentedToServerRequiringClientCertificate_completesHandshake() async throws {
        // `LocalServer.TLSOption.client(_:)` (server-side mTLS verification, needed to even
        // construct the `LocalServer` this test drives against) has no Network.framework
        // equivalent under a NIOCore-free build -- see that type's own doc comment. Under
        // NIOCore this whole body runs for real; without it, everything from construction
        // onward is expected to throw, so it is wrapped wholesale rather than gated
        // piecemeal.
        func run() async throws {
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
            let serverTrustDescriptor = try Internals.ServerTrustPolicy.resolve(from: secureConnection)
                .descriptor()

            // Simulates a relaunch: the only things carried forward are the two `Descriptor`s,
            // JSON round-tripped, exactly like `taskDescription`.
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

            // When / Then
            func verify() async throws {
                let (handle, intermediates) = try rebuiltClientIdentityDescriptor.makeIdentity()

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

            #if os(macOS) || !canImport(Darwin)
            try await verify()
            #else
            await withKnownIssue(
                "no Keychain Sharing entitlement on this platform's SwiftPM-generated Xcode scheme; see this test's own doc comment"
            ) {
                try await verify()
            }
            #endif
        }

        #if canImport(NIOCore)
        try await run()
        #else
        await withKnownIssue(
            """
            LocalServer.TLSOption.client(_:) (server-side mTLS verification) has no \
            Network.framework equivalent under a NIOCore-free build
            """
        ) {
            try await run()
        }
        #endif
    }
}

/// Answers both halves of an mTLS handshake by hand: the client-certificate credential directly
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
