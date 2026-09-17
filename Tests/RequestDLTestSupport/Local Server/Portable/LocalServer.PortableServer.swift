//
// See LICENSE for this package's licensing information.
//

#if !canImport(NIOCore)

import Network
import RequestDLInternals
import Security
import SwiftAsyncStream

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

extension LocalServer {

    enum PortableServerError: Swift.Error, Sendable {
        case identityCreationFailed
        case invalidPort
        case listenerFailed(NWError)
        case listenerCancelledBeforeReady
        case malformedRequest
    }

    /// `ServerManager`'s Network.framework counterpart: one `NWListener` per port, reused across
    /// every ``LocalServer`` built for the same ``Configuration``, exactly like the NIO backend's
    /// own `_channels` cache.
    final class PortableServerManager: @unchecked Sendable {

        // MARK: - Internal static properties

        static let shared = PortableServerManager()
        static let stress = PortableServerManager()

        // MARK: - Private properties

        private let lock = AsyncLock()

        // MARK: - Unsafe properties

        private var _listeners: [Configuration: (PortableListener, ResponseQueue)] = [:]

        // MARK: - Internal methods

        func remove(_ configuration: Configuration) async throws {
            try await lock.withLock {
                _listeners[configuration]?.0.close()
                _listeners[configuration] = nil
            }
        }

        func listener(_ configuration: Configuration) async throws -> (PortableListener, ResponseQueue) {
            try await lock.withLock {
                if let existing = _listeners[configuration] {
                    return existing
                }

                let responseQueue = ResponseQueue()
                let listener = try PortableListener(configuration: configuration, responseQueue: responseQueue)
                try await listener.start()
                _listeners[configuration] = (listener, responseQueue)
                return (listener, responseQueue)
            }
        }
    }

    /// One `NWListener`, bound and presenting a `SecIdentity` for TLS, handing every accepted
    /// `NWConnection` off to its own ``PortableConnection``.
    final class PortableListener: @unchecked Sendable {

        // MARK: - Private properties

        private let listener: NWListener
        private let queue: DispatchQueue

        // MARK: - Unsafe properties

        // Kept alive for the listener's lifetime: releasing the last `IdentityHandle` for a
        // label tears down its Keychain items (see `Internals.IdentityManager`), which would
        // pull the certificate/key out from under any TLS handshake still in flight.
        private let identityHandle: Internals.IdentityHandle

        // MARK: - Inits

        init(configuration: Configuration, responseQueue: ResponseQueue) throws {
            let identityHandle = try configuration.option.serverIdentity()

            guard let secIdentity = sec_identity_create(identityHandle.identity) else {
                throw PortableServerError.identityCreationFailed
            }

            let tlsOptions = NWProtocolTLS.Options()
            sec_protocol_options_set_local_identity(tlsOptions.securityProtocolOptions, secIdentity)

            let tcpOptions = NWProtocolTCP.Options()
            let parameters = NWParameters(tls: tlsOptions, tcp: tcpOptions)
            parameters.allowLocalEndpointReuse = true

            guard let port = NWEndpoint.Port(rawValue: UInt16(configuration.port)) else {
                throw PortableServerError.invalidPort
            }

            let queue = DispatchQueue(label: "com.requestdl.tests.local-server.portable.\(configuration.port)")

            self.identityHandle = identityHandle
            self.queue = queue
            self.listener = try NWListener(using: parameters, on: port)

            listener.newConnectionHandler = { connection in
                PortableConnection(connection: connection, responseQueue: responseQueue, queue: queue).start()
            }
        }

        // MARK: - Internal methods

        func start() async throws {
            let box = ContinuationBox<Void, Swift.Error>()

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Swift.Error>) in
                box.set(continuation)

                listener.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        box.resume(returning: ())
                    case .failed(let error):
                        box.resume(throwing: PortableServerError.listenerFailed(error))
                    case .cancelled:
                        box.resume(throwing: PortableServerError.listenerCancelledBeforeReady)
                    default:
                        break
                    }
                }

                listener.start(queue: queue)
            }
        }

        func close() {
            listener.cancel()
        }
    }
}

/// A `CheckedContinuation`, resumable exactly once, from inside a `@Sendable` callback that may
/// fire more than once (`NWListener`/`NWConnection`'s state handlers do, across the states this
/// package doesn't care about). `Lock`-guarded rather than relying on queue confinement, since
/// nothing here promises every state update actually arrives serialized on one queue.
private final class ContinuationBox<Value: Sendable, Failure: Swift.Error>: @unchecked Sendable {

    private let lock = Lock()
    private var continuation: CheckedContinuation<Value, Failure>?

    func set(_ continuation: CheckedContinuation<Value, Failure>) {
        lock.withLock {
            self.continuation = continuation
        }
    }

    func resume(returning value: Value) {
        let continuation = lock.withLock { () -> CheckedContinuation<Value, Failure>? in
            defer { self.continuation = nil }
            return self.continuation
        }

        continuation?.resume(returning: value)
    }

    func resume(throwing error: Failure) {
        let continuation = lock.withLock { () -> CheckedContinuation<Value, Failure>? in
            defer { self.continuation = nil }
            return self.continuation
        }

        continuation?.resume(throwing: error)
    }
}

#endif
