/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct ModifiersCollectBytesTests {

    @Test
    func collect_whenUploadStep_shouldBeValid() async throws {
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
        .collectBytes()
        .extractPayload()
        .result()

        let data = try await Data(Array(bytes).joined())

        // Then
        #expect(try HTTPResult(data).response == message)
    }
}
