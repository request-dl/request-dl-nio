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
        let uri = "/" + UUID().uuidString
        defer { localServer.cleanup(at: uri) }

        let resource = Certificates().server()
        let message = "Hello World"

        let response = try LocalServer.ResponseConfiguration(
            jsonObject: message
        )

        localServer.insert(response, at: uri)

        // When
        let bytes = try await UploadTask {
            BaseURL(localServer.baseURL)
            Path(uri)
            SecureConnection {
                Trusts {
                    RequestDL.Certificate(resource.certificateURL.absolutePath(percentEncoded: false))
                }
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
                Trusts {
                    RequestDL.Certificate(resource.certificateURL.absolutePath(percentEncoded: false))
                }
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
                Trusts {
                    RequestDL.Certificate(resource.certificateURL.absolutePath(percentEncoded: false))
                }
            }
        }
        .ignoresProgress()
        .extractPayload()
        .result()

        // Then
        #expect(try HTTPResult(data).response == message)
    }
}
