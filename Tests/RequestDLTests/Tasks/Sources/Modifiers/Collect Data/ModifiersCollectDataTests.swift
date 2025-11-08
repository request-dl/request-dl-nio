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
        defer { localServer.cleanup() }

        let resource = Certificates().server()
        let message = "Hello World"

        let response = try LocalServer.ResponseConfiguration(
            jsonObject: message
        )

        localServer.insert(response)

        // When
        let data = try await UploadTask {
            BaseURL(localServer.baseURL)
            Path("index")
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
        defer { localServer.cleanup() }

        let resource = Certificates().server()
        let message = "Hello World"

        let response = try LocalServer.ResponseConfiguration(
            jsonObject: message
        )

        localServer.insert(response)

        // When
        let data = try await UploadTask {
            BaseURL(localServer.baseURL)
            Path("index")
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
        defer { localServer.cleanup() }

        let resource = Certificates().server()
        let message = "Hello World"

        let response = try LocalServer.ResponseConfiguration(
            jsonObject: message
        )

        localServer.insert(response)

        // When
        let data = try await UploadTask {
            BaseURL(localServer.baseURL)
            Path("index")
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
