//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import struct Foundation.UUID
import struct Foundation.URL
#endif

// `session_whenUploadingFile_shouldBeValid` pushes 100MB through the same 2-thread event loop
// group (`Session.provider`, see below) that the other three tests here use for a prompt
// response; swift-testing runs `@Test`s in a suite concurrently by default, and the upload
// starves the group's threads until the others hit `connectTimeout`. `.serialized` keeps this
// suite's tests from overlapping, which the connection-pool tuning below alone didn't fix.
@Suite(.serialized)
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

            // Same dedicated pool `Session.localServer` (see LocalServerSession.swift) gives the
            // rest of this suite family, not `.shared`. `.shared` is `MultiThreadedEventLoopGroup
            // .shared` — one thread, process-wide — and this file's own
            // `session_whenUploadingFile_shouldBeValid` pushes 100MB through it in the same run
            // as three tests that expect a prompt response; on that single thread, the upload
            // starves the others until they hit `connectTimeout`.
            configuration.connectionPool.concurrentHTTP1ConnectionsPerHostSoftLimit = 64

            session = Internals.Session(
                provider: .identified("com.requestdl.tests.local-server", numberOfThreads: 2),
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

        var requestConfiguration = RequestConfiguration()
        requestConfiguration.baseURL = "https://localhost:8888"
        requestConfiguration.pathComponents = [testState.uri.trimmingCharacters(in: .init(charactersIn: "/"))]

        // When
        let task = try await session.execute(
            requestConfiguration: requestConfiguration,
            dataCache: .init(),
            logger: nil
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
        let data = await Data.randomData(length: length)

        var requestConfiguration = RequestConfiguration()
        requestConfiguration.baseURL = "https://localhost:8888"
        requestConfiguration.pathComponents = [testState.uri.trimmingCharacters(in: .init(charactersIn: "/"))]
        requestConfiguration.method = "POST"
        requestConfiguration.body = await RequestBody(buffers: [
            Internals.DataBuffer(data)
        ])

        // When
        let task = try await session.execute(
            requestConfiguration: requestConfiguration,
            dataCache: .init(),
            logger: nil
        )

        let result = try await Array(task())

        // Then
        let uploadSteps = result.compactMap { step -> UploadStep? in
            guard case .upload(let step) = step else {
                return nil
            }

            return step
        }

        // Whatever the chunking policy is, every part has to report the same total and the
        // parts have to add up to the body. Asserting a step count instead pinned the policy.
        #expect(uploadSteps.count == result.count - 1)
        #expect(uploadSteps.allSatisfy { $0.totalSize == length })
        #expect(uploadSteps.map(\.chunkSize).reduce(.zero, +) == length)

        // Regression guard: a body this small must go out in one chunk, not one byte at a time.
        #expect(uploadSteps.count == 1)

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

        var requestConfiguration = RequestConfiguration()
        requestConfiguration.baseURL = "https://localhost:8888"
        requestConfiguration.pathComponents = [testState.uri.trimmingCharacters(in: .init(charactersIn: "/"))]
        requestConfiguration.method = "POST"
        requestConfiguration.body = RequestBody(buffers: [])

        // When
        let task = try await session.execute(
            requestConfiguration: requestConfiguration,
            dataCache: .init(),
            logger: nil
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

        defer { url.scheduleRemoval() }
        try await url.createPathIfNeeded()

        var fileBuffer = await Internals.FileBuffer(url)
        await fileBuffer.writeData(Data.randomData(length: length))

        let response = try LocalServer.ResponseConfiguration(
            jsonObject: message
        )

        localServer.insert(response, at: testState.uri)

        // When
        var requestConfiguration = RequestConfiguration()
        requestConfiguration.baseURL = "https://\(localServer.baseURL)"
        requestConfiguration.pathComponents = [testState.uri.trimmingCharacters(in: .init(charactersIn: "/"))]
        requestConfiguration.method = "POST"
        requestConfiguration.body = RequestBody(
            chunkSize: fragment,
            buffers: [fileBuffer]
        )

        var secureConnection = Internals.SecureConnection()
        secureConnection.trustRoots = .certificates([
            .init(certificates.certificateURL.absolutePath(percentEncoded: false), format: .pem)
        ])

        var configuration = testingSession.configuration
        configuration.secureConnection = secureConnection

        let session = Internals.Session(
            provider: testingSession.provider,
            configuration: configuration
        )

        let task = try await session.execute(
            requestConfiguration: requestConfiguration,
            dataCache: .init(),
            logger: nil
        )

        var uploadedBytes: [Int] = []
        var download: (ResponseHead, Data)?

        for try await result in task() {
            switch result {
            case .upload(let step):
                print("Send \(step.chunkSize) bytes of \(step.totalSize) (\(uploadedBytes.count))")
                uploadedBytes.append(step.chunkSize)
            case .download(let step):
                print("Head \(step.head.status.code) \(step.head.status.reason)")
                download = (step.head, try await Data(Array(step.bytes).joined()))
            }
        }

        // Then
        let uploadedTotal = uploadedBytes.reduce(.zero, +)

        #expect(fileBuffer.writerIndex == length)
        #expect(uploadedTotal == length)
        #expect(uploadedBytes.allSatisfy { $0 <= fragment })
        #expect(download != nil)
        #expect(download?.0.status.code == 200)
        #expect(
            try (download?.1).map(HTTPResult<String>.init)
                == HTTPResult(
                    receivedBytes: length,
                    response: message
                )
        )
    }
}
