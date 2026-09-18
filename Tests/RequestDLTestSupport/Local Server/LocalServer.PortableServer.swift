//
// See LICENSE for this package's licensing information.
//

// The Network.framework counterpart to `LocalServer.swift`'s NIOSSL/`ServerBootstrap`-backed
// `ServerManager` implementation: everything here exists only because that one needs `NIOCore` to
// compile at all. See `LocalServer.PortableConnection.swift` for the hand-rolled HTTP/1.1 half of
// this (there is no Network.framework equivalent of NIOHTTP1's `configureHTTPServerPipeline()` to
// build this on top of instead).
#if !canImport(NIOCore)

import Foundation
import Network
import RequestDLInternals
import SwiftAsyncStream

extension LocalServer {

    /// One TLS-terminated `NWListener`, standing in for the `Channel` a NIOSSL-backed
    /// `LocalServer` binds to. Only `TLSOption.none` (the standard test server certificate, no
    /// client verification) is reachable: see `TLSOption.makeLocalIdentity()`'s own doc comment
    /// for why `.psk`/`.client` throw instead.
    final class PortableServer: @unchecked Sendable {

        struct InvalidPortError: Swift.Error, CustomStringConvertible {
            let port: UInt
            var description: String { "\(port) is not a valid TCP port (must fit in a UInt16)." }
        }

        struct IdentityCreationError: Swift.Error, CustomStringConvertible {
            var description: String { "sec_identity_create(_:) returned nil for the server's SecIdentity." }
        }

        // MARK: - Private properties

        private let listener: NWListener
        private let queue: DispatchQueue
        private let responseQueue: ResponseQueue

        // Keeps the `SecIdentity`'s backing Keychain items alive for as long as this listener is:
        // `Internals.IdentityHandle.deinit` removes them once nothing references it anymore.
        private let identityHandle: Internals.IdentityHandle

        private let connectionsLock = Lock()
        private var _connections: [ObjectIdentifier: Connection] = [:]

        // MARK: - Inits

        init(configuration: Configuration, responseQueue: ResponseQueue) async throws {
            let identityHandle = try configuration.option.makeLocalIdentity()

            guard let secIdentity = sec_identity_create(identityHandle.identity) else {
                throw IdentityCreationError()
            }

            let tlsOptions = NWProtocolTLS.Options()
            sec_protocol_options_set_local_identity(tlsOptions.securityProtocolOptions, secIdentity)

            let parameters = NWParameters(tls: tlsOptions, tcp: NWProtocolTCP.Options())
            // Mirrors the NIOCore side's `so_reuseaddr`: a previous run's listener on this same
            // port may still be winding down when the next one starts.
            parameters.allowLocalEndpointReuse = true

            guard let port = NWEndpoint.Port(rawValue: UInt16(configuration.port)) else {
                throw InvalidPortError(port: configuration.port)
            }

            let listener = try NWListener(using: parameters, on: port)
            let queue = DispatchQueue(label: "com.requestdl.tests.local-server.\(configuration.port)")

            self.listener = listener
            self.identityHandle = identityHandle
            self.queue = queue
            self.responseQueue = responseQueue

            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let box = StartContinuationBox(continuation)

                listener.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        box.resume()
                    case .failed(let error):
                        box.resume(throwing: error)
                    default:
                        break
                    }
                }

                listener.start(queue: queue)
            }
        }

        // MARK: - Internal methods

        func close() async throws {
            listener.cancel()

            let connections = connectionsLock.withLock { () -> [Connection] in
                let values = Array(_connections.values)
                _connections = [:]
                return values
            }

            for connection in connections {
                connection.cancel()
            }
        }

        // MARK: - Private methods

        private func accept(_ connection: NWConnection) {
            let handler = Connection(
                connection: connection,
                queue: queue,
                responseQueue: responseQueue,
                onClose: { [weak self] finishedHandler in
                    self?.connectionsLock.withLock {
                        self?._connections.removeValue(forKey: ObjectIdentifier(finishedHandler))
                    }
                }
            )

            connectionsLock.withLock {
                _connections[ObjectIdentifier(handler)] = handler
            }

            handler.start()
        }
    }
}

/// Bridges `NWListener.stateUpdateHandler` (called repeatedly) to a `CheckedContinuation` (usable
/// exactly once): resumes on the first `.ready`/`.failed`, ignores every later call. Mirrors
/// `InternalsSOCKSProxyDictionaryPlatformTests`'s own `ContinuationBox`.
private final class StartContinuationBox: @unchecked Sendable {

    private let lock = Lock()
    private var continuation: CheckedContinuation<Void, Error>?

    init(_ continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    func resume() { take()?.resume() }
    func resume(throwing error: Error) { take()?.resume(throwing: error) }

    private func take() -> CheckedContinuation<Void, Error>? {
        lock.lock()
        defer { lock.unlock() }
        let continuation = self.continuation
        self.continuation = nil
        return continuation
    }
}

#endif
