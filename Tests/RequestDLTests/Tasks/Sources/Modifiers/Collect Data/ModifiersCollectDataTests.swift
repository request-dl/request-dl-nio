/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct ModifiersCollectDataTests {

    @Test
    func collect_whenIsResultOfAsyncBytes() async throws {
        // Given
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString
        defer { localServer.cleanup(at: uri) }

        let resource = Certificates().server()
        let message = "Hello World"

        let response = try LocalServer.ResponseConfiguration(
            jsonObject: message
        )

        localServer.insert(response, at: uri)

        // When
        let data = try await UploadTask {
            BaseURL(localServer.baseURL)
            Path(uri)
            SecureConnection {
                #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
                DefaultTrusts()
                AdditionalTrusts {
                    RequestDL.Certificate(resource.certificateURL.absolutePath(percentEncoded: false))
                }
                #else
                Trusts {
                    RequestDL.Certificate(resource.certificateURL.absolutePath(percentEncoded: false))
                }
                #endif
            }
        }
        .collectBytes()
        .collectData()
        .extractPayload()
        .result()

        // Then
        #expect(try HTTPResult(data).response == message)
    }

    @Test
    func collect_whenIsAsyncBytes() async throws {
        // Given
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString
        defer { localServer.cleanup(at: uri) }

        let resource = Certificates().server()
        let message = "Hello World"

        let response = try LocalServer.ResponseConfiguration(
            jsonObject: message
        )

        localServer.insert(response, at: uri)

        // When
        let data = try await UploadTask {
            BaseURL(localServer.baseURL)
            Path(uri)
            SecureConnection {
                #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
                DefaultTrusts()
                AdditionalTrusts {
                    RequestDL.Certificate(resource.certificateURL.absolutePath(percentEncoded: false))
                }
                #else
                Trusts {
                    RequestDL.Certificate(resource.certificateURL.absolutePath(percentEncoded: false))
                }
                #endif
            }
        }
        .collectBytes()
        .extractPayload()
        .collectData()
        .result()

        // Then
        #expect(try HTTPResult(data).response == message)
    }

    @Test
    func collect_whenIsAsyncResponse() async throws {
        // Given
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString
        defer { localServer.cleanup(at: uri) }

        let resource = Certificates().server()
        let message = "Hello World"

        let response = try LocalServer.ResponseConfiguration(
            jsonObject: message
        )

        localServer.insert(response, at: uri)

        // When
        let data = try await UploadTask {
            BaseURL(localServer.baseURL)
            Path(uri)
            SecureConnection {
                #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
                DefaultTrusts()
                AdditionalTrusts {
                    RequestDL.Certificate(resource.certificateURL.absolutePath(percentEncoded: false))
                }
                #else
                Trusts {
                    RequestDL.Certificate(resource.certificateURL.absolutePath(percentEncoded: false))
                }
                #endif
            }
        }
        .collectData()
        .extractPayload()
        .result()

        // Then
        #expect(try HTTPResult(data).response == message)
    }
}
