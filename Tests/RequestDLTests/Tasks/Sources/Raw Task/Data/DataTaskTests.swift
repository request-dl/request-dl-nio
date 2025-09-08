/*
 See LICENSE for this package's licensing information.
*/

import XCTest
import NIOSSL
@testable import RequestDL

class DataTaskTests: XCTestCase {

    var localServer: LocalServer?

    override func setUp() async throws {
        try await super.setUp()
        localServer = try await .init(.standard)
        localServer?.cleanup()
    }

    override func tearDown() async throws {
        try await super.tearDown()
        localServer?.cleanup()
        localServer = nil
    }

    func testDataTask() async throws {
        // Given
        let localServer = try XCTUnwrap(localServer)
        
        let certificate = Certificates().server()
        let output = "Hello World"

        let response = try LocalServer.ResponseConfiguration(
            jsonObject: output
        )

        localServer.insert(response)

        // When
        let data = try await DataTask {
            BaseURL(localServer.baseURL)
            Path("index")

            SecureConnection {
                Trusts(certificate.certificateURL.absolutePath(percentEncoded: false))
            }
        }
        .extractPayload()
        .result()

        let result = try HTTPResult<String>(data)

        // Then
        XCTAssertEqual(result.response, output)
    }

    func testDataTask_whenCAEnabled() async throws {
        // Given
        let server = Certificates().server()
        let client = Certificates().client()

        let localServer = try await LocalServer(
            LocalServer.Configuration(
                host: "localhost",
                port: 8887,
                option: .client(client)
            )
        )

        let output = "Hello World"

        let response = try LocalServer.ResponseConfiguration(
            jsonObject: output
        )

        localServer.insert(response)

        // When
        let data = try await DataTask {
            BaseURL(localServer.baseURL)
            Path("index")

            SecureConnection {
                Trusts(server.certificateURL.absolutePath(percentEncoded: false))
                RequestDL.Certificates(client.certificateURL.absolutePath(percentEncoded: false))
                PrivateKey(client.privateKeyURL.absolutePath(percentEncoded: false))
            }
            .verification(.fullVerification)
        }
        .extractPayload()
        .result()

        let result = try HTTPResult<String>(data)

        // Then
        XCTAssertEqual(result.response, output)
    }
}

extension DataTaskTests {

    private final class PSKClientIdentityResolver: SSLPSKIdentityResolver {

        let key: String
        let identity: String

        init(key: String, identity: String) {
            self.key = key
            self.identity = identity
        }

        func callAsFunction(_ hint: String) throws -> PSKClientIdentityResponse {
            var bytes = NIOSSLSecureBytes()
            bytes.append(key.utf8)
            bytes.append(":\(identity)".utf8)
            bytes.append(":\(identity)".utf8)
            bytes.append(":pskHint".utf8)
            return.init(key: bytes, identity: identity)
        }
    }

    func testDataTask_whenPSK() async throws {
        // Given
        let output = "Hello World"

        let identity = "client"
        let key = """
        ff135dfc9c802f584fd8b7bb3284fae0e1c404e4f8ac9217ff1b1bdecb\
        d4cfa5651253143700a94c89227f5db03ed2de86a2914b4da0259901a4\
        bbaf8a1dee0f
        """

        let localServer = try await LocalServer(
            LocalServer.Configuration(
                host: "localhost",
                port: 8886,
                option: .psk(Data(key.utf8), identity)
            )
        )

        let response = try LocalServer.ResponseConfiguration(
            jsonObject: output
        )

        localServer.insert(response)

        // When
        let data = try await DataTask {
            BaseURL(localServer.baseURL)
            Path("index")

            SecureConnection {
                PSKIdentity(
                    PSKClientIdentityResolver(
                        key: key,
                        identity: identity
                    )
                )
                .hint("pskHint")
            }
            .verification(.none)
            .version(minimum: .v1, maximum: .v1_2)
        }
        .extractPayload()
        .result()

        let result = try HTTPResult<String>(data)

        // Then
        XCTAssertEqual(result.response, output)
    }
}
