//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals
import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

#if canImport(NIOCore)

/// `/echo` and `/echo/` are different resources on many servers: the path the first request of a
/// `URLOverride` is sent to keeps the trailing slash the request declared, as every hop after it
/// does.
struct URLOverrideTrailingSlashTests {

    @Test(arguments: TransferTestExecutor.allCases, ["echo/", "echo", "a/b/"])
    func dataTask_whenAnOverrideCoversTheRequest_keepsTheTrailingSlashOfThePath(
        executor: TransferTestExecutor,
        path: String
    ) async throws {
        // Given
        let server = try await ScriptedServer { _ in .ok() }

        // When
        _ = try await DataTask {
            BaseURL("staging.example.test")
            Path(path)

            URLOverride("http://127.0.0.1:\(server.port)", from: "https://staging.example.test")

            executor.pinnedSession
        }
        .result()

        let requests = server.requests
        await server.shutdown()

        // Then
        #expect(requests.map(\.uri) == ["/" + path])
    }

    @Test(arguments: TransferTestExecutor.allCases)
    func dataTask_whenTheOverrideAddsAPrefixToThePath_keepsTheTrailingSlashOfThePath(
        executor: TransferTestExecutor
    ) async throws {
        // Given
        let server = try await ScriptedServer { _ in .ok() }

        // When
        _ = try await DataTask {
            BaseURL("staging.example.test")
            Path("echo/")

            URLOverride("http://127.0.0.1:\(server.port)/v2", from: "https://staging.example.test")

            executor.pinnedSession
        }
        .result()

        let requests = server.requests
        await server.shutdown()

        // Then
        #expect(requests.map(\.uri) == ["/v2/echo/"])
    }
}

#endif
