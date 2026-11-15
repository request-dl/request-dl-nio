//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL
@testable import RequestDLInternals

#if canImport(NIOCore)
import NIOCore
import NIOPosix
#endif

/// A request whose method is not an HTTP token is refused before it is built, whichever executor
/// would run it. A method is written as it is on the request line: `.nio` (AsyncHTTPClient) turned
/// an unknown one into `.RAW(value:)` and wrote it verbatim, so one carrying `\r\n` added lines of
/// its own, and a whole second request in HTTP/1.1.
struct RequestConfigurationMethodValidationTests {

    static let invalidMethods = [
        "GET / HTTP/1.1\r\nX: y\r\n\r\nPOST",
        "GET /",
        "GET\r\n",
        "G\u{0}ET",
        "GE T",
        "GET\t",
        "GET:",
        "G(T",
        "GÉT",
        "",
    ]

    static let validMethods = ["GET", "POST", "PATCH", "PROPFIND", "M-SEARCH", "get", "X.custom_1~", "A!#$%&'*+^`|"]

    private func configuration(method: String?) -> RequestConfiguration {
        var configuration = RequestConfiguration()
        configuration.baseURL = "https://example.com"
        configuration.method = method
        return configuration
    }

    /// `CURLTask(allowing: [])` is how a pasted command reaches this: `-X` is not behind any
    /// capability, and the request has to be refused before it is sent.
    @Test(arguments: [
        #"curl -X $'GET / HTTP/1.1\r\nX: y\r\n\r\nPOST' http://127.0.0.1:9/"#,
        #"curl -X 'GE T' http://127.0.0.1:9/"#,
    ])
    func curlTask_whenMethodIsNotAToken_failsBeforeAnythingIsSent(_ command: String) async {
        await #expect(throws: Internals.InvalidMethodError.self) {
            _ = try await CURLTask(command, allowing: []).result()
        }
    }

    #if canImport(NIOCore)
    @Test(arguments: invalidMethods)
    func nio_whenMethodIsNotAToken_throws(_ method: String) throws {
        // Given
        let configuration = configuration(method: method)

        // Then
        #expect(throws: (any Error).self) {
            try configuration.build(eventLoop: MultiThreadedEventLoopGroup.singleton.any())
        }
    }

    @Test(arguments: validMethods)
    func nio_whenMethodIsAToken_isSentAsItIs(_ method: String) throws {
        // Given
        let configuration = configuration(method: method)

        // When
        let request = try configuration.build(eventLoop: MultiThreadedEventLoopGroup.singleton.any())

        // Then
        #expect(request.method.rawValue == method)
    }

    @Test func nio_whenHeaderNameIsEmpty_throws() throws {
        var configuration = configuration(method: nil)
        configuration.headers.add(name: "", value: "v")

        #expect(throws: (any Error).self) {
            try configuration.build(eventLoop: MultiThreadedEventLoopGroup.singleton.any())
        }
    }

    @Test func nio_whenMethodIsNil_isGET() throws {
        let request = try configuration(method: nil)
            .build(eventLoop: MultiThreadedEventLoopGroup.singleton.any())

        #expect(request.method == .GET)
    }
    #endif

    #if canImport(Darwin)
    @Test(arguments: invalidMethods)
    func urlSession_whenMethodIsNotAToken_throws(_ method: String) async throws {
        // Given
        let configuration = configuration(method: method)

        // Then
        #expect(throws: (any Error).self) {
            try configuration.buildURLRequestWithoutBody()
        }

        await #expect(throws: (any Error).self) {
            try await configuration.buildURLRequest()
        }
    }

    @Test func urlSession_whenHeaderNameIsEmpty_throws() throws {
        var configuration = configuration(method: nil)
        configuration.headers.add(name: "", value: "v")

        #expect(throws: (any Error).self) {
            try configuration.buildURLRequestWithoutBody()
        }
    }

    @Test(arguments: validMethods)
    func urlSession_whenMethodIsAToken_isKept(_ method: String) throws {
        let request = try configuration(method: method).buildURLRequestWithoutBody()

        #expect(request.httpMethod?.lowercased() == method.lowercased())
    }
    #endif
}
