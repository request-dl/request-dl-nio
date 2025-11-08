/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct ModifiersIgnoresProgressTests {

    @Test
    func ignores_whenUploadStep_shouldBeValid() async throws {
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
        let bytes = try await UploadTask {
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
        .ignoresUploadProgress()
        .extractPayload()
        .result()

        let data = try await Data(Array(bytes).joined())

        // Then
        #expect(try HTTPResult(data).response == message)
    }

    @Test
    func ignores_whenDownloadStep_shouldBeValid() async throws {
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
        .ignoresUploadProgress()
        .ignoresDownloadProgress()
        .extractPayload()
        .result()

        // Then
        #expect(try HTTPResult(data).response == message)
    }

    @Test
    func ignores_whenSkipProgress_shouldBeValid() async throws {
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
        .ignoresProgress()
        .extractPayload()
        .result()

        // Then
        #expect(try HTTPResult(data).response == message)
    }
}
