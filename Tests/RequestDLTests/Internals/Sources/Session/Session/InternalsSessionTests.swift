/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct InternalsSessionTests {

    final class TestState: Sendable {

        let uri: String
        let localServer: LocalServer
        let session: Internals.Session

        init() async throws {
            uri = "/" + UUID().uuidString
            localServer = try await .init(.standard)
            localServer.cleanup(at: uri)

            var configuration = Internals.Session.Configuration()
            var secureConnection = Internals.SecureConnection()

            secureConnection.certificateVerification = .some(.none)
            configuration.secureConnection = secureConnection

            session = Internals.Session(
                provider: .shared,
                configuration: configuration
            )
        }

        deinit {
            localServer.cleanup(at: uri)
        }
    }

    @Test
    func session_whenPerformingGet_shouldBeValid() async throws {
        let testState = try await TestState()
        // Given
        let session = testState.session

        var request = Internals.Request()
        request.baseURL = "https://localhost:8888"
        request.pathComponents = [testState.uri.trimmingCharacters(in: .init(charactersIn: "/"))]

        // When
        let task = try await session.execute(
            request: request,
            dataCache: .init()
        )

        let result = try await Array(task())

        // Then
        #expect(result.count == 1)

        guard case .download? = result.first else {
            Issue.record("The obtained result is different from the expected result")
            return
        }
    }

    @Test
    func session_whenPerformingPostUploadingData_shouldBeValid() async throws {
        let testState = try await TestState()
        // Given
        let session = testState.session

        let length = 1_023
        let data = Data.randomData(length: length)

        var request = Internals.Request()
        request.baseURL = "https://localhost:8888"
        request.pathComponents = [testState.uri.trimmingCharacters(in: .init(charactersIn: "/"))]
        request.method = "POST"
        request.body = Internals.Body(buffers: [
            Internals.DataBuffer(data)
        ])

        // When
        let task = try await session.execute(
            request: request,
            dataCache: .init()
        )
        let result = try await Array(task())

        // Then
        #expect(result.count == length + 1)
        #expect(
            Array(result[0..<length]) == (0..<length).map { _ in .upload(.init(chunkSize: 1, totalSize: length)) }
        )

        guard case .download? = result.last else {
            Issue.record("The obtained result is different from the expected result")
            return
        }
    }

    @Test
    func session_whenPerformingPostEmptyData_shouldBeValid() async throws {
        let testState = try await TestState()
        // Given
        let session = testState.session

        var request = Internals.Request()
        request.baseURL = "https://localhost:8888"
        request.pathComponents = [testState.uri.trimmingCharacters(in: .init(charactersIn: "/"))]
        request.method = "POST"
        request.body = Internals.Body(buffers: [])

        // When
        let task = try await session.execute(
            request: request,
            dataCache: .init()
        )
        let result = try await Array(task())

        // Then
        #expect(result.count == 1)

        guard case .download? = result.first else {
            Issue.record("The obtained result is different from the expected result")
            return
        }
    }

    // swiftlint:disable function_body_length
    @Test
    func session_whenUploadingFile_shouldBeValid() async throws {
        let testState = try await TestState()
        // Given
        let localServer = testState.localServer
        let testingSession = testState.session

        let certificates = Certificates().server()
        let message = "Hello World"

        let length = 100_000_000
        let fragment = 1_024 * 8

        let url = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("UploadingFile.txt")

        defer { try? url.removeIfNeeded() }
        try url.createPathIfNeeded()

        var fileBuffer = Internals.FileBuffer(url)
        fileBuffer.writeData(Data.randomData(length: length))

        let response = try LocalServer.ResponseConfiguration(
            jsonObject: message
        )

        localServer.insert(response, at: testState.uri)

        // When
        var request = Internals.Request()
        request.baseURL = "https://\(localServer.baseURL)"
        request.pathComponents = [testState.uri.trimmingCharacters(in: .init(charactersIn: "/"))]
        request.method = "POST"
        request.body = Internals.Body(
            chunkSize: fragment,
            buffers: [fileBuffer]
        )

        var secureConnection = Internals.SecureConnection()
        secureConnection.trustRoots = .certificates([
            .init(certificates.certificateURL.absolutePath(percentEncoded: false), format: .pem)
        ])

        var configuration = testingSession.configuration
        configuration.secureConnection = secureConnection
        configuration.disableNetworkFramework = true

        let session = Internals.Session(
            provider: testingSession.provider,
            configuration: configuration
        )

        let task = try await session.execute(
            request: request,
            dataCache: .init()
        )

        var uploadedBytes: [Int] = []
        var download: (ResponseHead, Data)?

        for try await result in task() {
            switch result {
            case .upload(let step):
                NSLog("Send %d bytes of %d (%d)", step.chunkSize, step.totalSize, uploadedBytes.count)
                uploadedBytes.append(step.chunkSize)
            case .download(let step):
                NSLog("Head %d %@", step.head.status.code, step.head.status.reason)
                download = (step.head, try await Data(Array(step.bytes).joined()))
            }
        }

        // Then
        #expect(uploadedBytes.count == Int(ceil(Double(length) / Double(fragment))))
        #expect(uploadedBytes.reduce(.zero, +) == fileBuffer.writerIndex)
        #expect(download != nil)
        #expect(download?.0.status.code == 200)
        #expect(
            try (download?.1).map(HTTPResult<String>.init) == HTTPResult(
                receivedBytes: length,
                response: message
            )
        )
    }
    // swiftlint:enable function_body_length
}
