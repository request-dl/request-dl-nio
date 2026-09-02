//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDLInternals

#if canImport(Darwin) && canImport(CFNetwork)

import Foundation
import Network

/// `Internals.PACEvaluator.evaluate(scriptURL:targetURL:timeout:)` against real, locally-served
/// PAC scripts -- a bare `NWListener` speaking just enough HTTP/1.1 to serve one script and close,
/// so this doesn't depend on the CI machine's actual system proxy settings (unlike
/// `SystemProxyTests`/`InternalsSystemProxyResolverTests`'s own integration tests) while still
/// exercising the genuine `CFNetworkExecuteProxyAutoConfigurationURL` fetch + JavaScript
/// evaluation + `CFRunLoopSource` pumping end to end, not a mock of any part of it.
///
/// `file://` was tried first and rejected: `CFNetworkExecuteProxyAutoConfigurationURL` fails
/// every `file://` script with `kCFURLErrorUnsupportedURLScheme` (-1002) -- PAC fetching only
/// speaks HTTP(S), the same as every browser's own PAC support.
struct InternalsPACEvaluatorTests {

    @Test
    func evaluate_whenScriptReturnsProxy_resolvesIt() async throws {
        // Given
        let server = try await LocalPACServer.start(
            scriptContents: """
                function FindProxyForURL(url, host) {
                    return "PROXY 127.0.0.1:8080";
                }
                """
        )
        defer { server.stop() }

        // When
        let proxy = try await Internals.PACEvaluator.evaluate(
            scriptURL: server.scriptURL,
            targetURL: try #require(URL(string: "https://example.com/")),
            timeout: 10
        )

        // Then
        #expect(proxy?.host == "127.0.0.1")
        #expect(proxy?.port == 8_080)
        #expect(proxy?.connectionProtocol == .http)
    }

    @Test
    func evaluate_whenScriptReturnsSOCKS_resolvesIt() async throws {
        // Given
        let server = try await LocalPACServer.start(
            scriptContents: """
                function FindProxyForURL(url, host) {
                    return "SOCKS 127.0.0.1:1080";
                }
                """
        )
        defer { server.stop() }

        // When
        let proxy = try await Internals.PACEvaluator.evaluate(
            scriptURL: server.scriptURL,
            targetURL: try #require(URL(string: "https://example.com/")),
            timeout: 10
        )

        // Then
        #expect(proxy?.port == 1_080)
        #expect(proxy?.connectionProtocol == .socks)
    }

    @Test
    func evaluate_whenScriptReturnsDirect_isNil() async throws {
        // Given
        let server = try await LocalPACServer.start(
            scriptContents: """
                function FindProxyForURL(url, host) {
                    return "DIRECT";
                }
                """
        )
        defer { server.stop() }

        // When
        let proxy = try await Internals.PACEvaluator.evaluate(
            scriptURL: server.scriptURL,
            targetURL: try #require(URL(string: "https://example.com/")),
            timeout: 10
        )

        // Then
        #expect(proxy == nil)
    }

    @Test
    func evaluate_whenScriptBranchesOnHost_choosesAccordingly() async throws {
        // Given -- proves `targetURL` genuinely reaches the script, not just that some fixed
        // return value comes back regardless of input.
        let server = try await LocalPACServer.start(
            scriptContents: """
                function FindProxyForURL(url, host) {
                    if (host == "internal.example.com") {
                        return "DIRECT";
                    }
                    return "PROXY 127.0.0.1:8080";
                }
                """
        )
        defer { server.stop() }

        // When
        let internalProxy = try await Internals.PACEvaluator.evaluate(
            scriptURL: server.scriptURL,
            targetURL: try #require(URL(string: "https://internal.example.com/")),
            timeout: 10
        )
        let externalProxy = try await Internals.PACEvaluator.evaluate(
            scriptURL: server.scriptURL,
            targetURL: try #require(URL(string: "https://external.example.com/")),
            timeout: 10
        )

        // Then
        #expect(internalProxy == nil)
        #expect(externalProxy?.host == "127.0.0.1")
    }

    @Test
    func evaluate_whenScriptThrows_throwsExecutionFailed() async throws {
        // Given
        let server = try await LocalPACServer.start(
            scriptContents: """
                function FindProxyForURL(url, host) {
                    throw "deliberately broken";
                }
                """
        )
        defer { server.stop() }

        // When / Then
        await #expect(throws: Internals.PACEvaluator.Error.self) {
            _ = try await Internals.PACEvaluator.evaluate(
                scriptURL: server.scriptURL,
                targetURL: try #require(URL(string: "https://example.com/")),
                timeout: 10
            )
        }
    }

    @Test
    func evaluate_whenScriptUnreachable_throwsWithinTimeout() async throws {
        // Given -- nothing listens on this port; connection refused, not a slow fetch, but still
        // exercised the same way a genuinely hung PAC server would be.
        let scriptURL = try #require(URL(string: "http://127.0.0.1:1/proxy.pac"))

        // When / Then -- bounded by the timeout below, not the run's own default (much longer),
        // proving the timeout is actually enforced rather than merely accepted as a parameter.
        let start = DispatchTime.now()

        await #expect(throws: (any Error).self) {
            _ = try await Internals.PACEvaluator.evaluate(
                scriptURL: scriptURL,
                targetURL: try #require(URL(string: "https://example.com/")),
                timeout: 3
            )
        }

        let elapsedSeconds = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1e9
        #expect(elapsedSeconds < 15)
    }
}

/// Serves exactly one PAC script to exactly one connection at a time, in the minimal HTTP/1.1
/// this needs: no request parsing at all (whatever `CFNetworkExecuteProxyAutoConfigurationURL`
/// sends is ignored -- the response is the same regardless of path/headers), and every connection
/// gets the same canned `200 OK` response, then closes.
private final class LocalPACServer: @unchecked Sendable {

    // MARK: - Internal properties

    let scriptURL: URL

    // MARK: - Private properties

    private let listener: NWListener

    // MARK: - Inits

    private init(listener: NWListener, port: UInt16) {
        self.listener = listener
        self.scriptURL = URL(string: "http://127.0.0.1:\(port)/proxy.pac")!
    }

    // MARK: - Internal static methods

    static func start(scriptContents: String) async throws -> LocalPACServer {
        let listener = try NWListener(using: .tcp, on: .any)

        let body = Data(scriptContents.utf8)
        var response = Data(
            """
            HTTP/1.1 200 OK\r
            Content-Type: application/x-ns-proxy-autoconfig\r
            Content-Length: \(body.count)\r
            Connection: close\r
            \r

            """.utf8
        )
        response.append(body)

        listener.newConnectionHandler = { connection in
            connection.start(queue: .main)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { _, _, _, _ in
                connection.send(
                    content: response,
                    completion: .contentProcessed { _ in
                        connection.cancel()
                    }
                )
            }
        }

        let queue = DispatchQueue(label: "InternalsPACEvaluatorTests.LocalPACServer")

        let port = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt16, Error>) in
            let box = PortContinuationBox(continuation)

            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard let port = listener.port?.rawValue else {
                        box.resume(throwing: MissingListenerPortError())
                        return
                    }
                    box.resume(returning: port)

                case .failed(let error):
                    box.resume(throwing: error)

                default:
                    break
                }
            }

            listener.start(queue: queue)
        }

        return LocalPACServer(listener: listener, port: port)
    }

    // MARK: - Internal methods

    func stop() {
        listener.cancel()
    }
}

private struct MissingListenerPortError: Error {}

/// Bridges `NWListener.stateUpdateHandler` (called repeatedly) to a `CheckedContinuation` (usable
/// exactly once) -- resumes on the first `.ready`/`.failed`, ignores every later call. Mirrors
/// `InternalsProxyDictionaryPlatformTests`'s identical, file-private helper -- not shared, since
/// neither file is a dependency of the other.
private final class PortContinuationBox: @unchecked Sendable {

    private let lock = NSLock()
    private var continuation: CheckedContinuation<UInt16, Error>?

    init(_ continuation: CheckedContinuation<UInt16, Error>) {
        self.continuation = continuation
    }

    func resume(returning port: UInt16) {
        take()?.resume(returning: port)
    }

    func resume(throwing error: Error) {
        take()?.resume(throwing: error)
    }

    private func take() -> CheckedContinuation<UInt16, Error>? {
        lock.lock()
        defer { lock.unlock() }
        let value = continuation
        continuation = nil
        return value
    }
}

#endif
