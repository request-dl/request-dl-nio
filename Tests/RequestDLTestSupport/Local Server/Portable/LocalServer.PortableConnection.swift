//
// See LICENSE for this package's licensing information.
//

#if !canImport(NIOCore)

import Network
import RequestDLInternals

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

extension LocalServer {

    /// Reads HTTP/1.1 requests off one accepted `NWConnection`, one at a time, answering each
    /// with ``LocalServer/makeResponseBody(configuration:receivedBytes:incomeHeaders:)`` the same
    /// way the NIO backend's `HTTPHandler` does, then keeps reading: `.urlSession` reuses a
    /// pooled connection across requests, so this has to support more than one request per
    /// connection, not just per process.
    final class PortableConnection: @unchecked Sendable {

        // MARK: - Private properties

        private let connection: NWConnection
        private let responseQueue: ResponseQueue
        private let queue: DispatchQueue

        // MARK: - Unsafe properties

        private var buffer: [UInt8] = []

        // MARK: - Inits

        init(connection: NWConnection, responseQueue: ResponseQueue, queue: DispatchQueue) {
            self.connection = connection
            self.responseQueue = responseQueue
            self.queue = queue
        }

        // MARK: - Internal methods

        func start() {
            connection.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.receiveMore()
                case .failed, .cancelled:
                    self?.connection.cancel()
                default:
                    break
                }
            }

            connection.start(queue: queue)
        }

        // MARK: - Private methods

        private func receiveMore() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1_024) { [weak self] data, _, isComplete, error in
                guard let self else { return }

                if let data, !data.isEmpty {
                    self.buffer.append(contentsOf: data)
                    self.drainBuffer()
                }

                guard error == nil, !isComplete else {
                    self.connection.cancel()
                    return
                }

                self.receiveMore()
            }
        }

        /// Responds to every complete request currently sitting in ``buffer``, in order, so a
        /// client that pipelines more than one request into the same `receive` callback still
        /// gets every response.
        private func drainBuffer() {
            while true {
                do {
                    guard let (request, consumed) = try PortableHTTPRequest.parse(buffer) else {
                        return
                    }

                    buffer.removeFirst(consumed)
                    respond(to: request)
                } catch {
                    connection.cancel()
                    return
                }
            }
        }

        private func respond(to request: PortableHTTPRequest) {
            let configuration = responseQueue.popLast(at: request.uri)

            let body = LocalServer.makeResponseBody(
                configuration: configuration,
                receivedBytes: request.body.count,
                incomeHeaders: request.headers
            )

            let headers = LocalServer.headers(
                configuration?.headers ?? .init(),
                replacingContentLengthWith: body?.count ?? .zero
            )

            let status = configuration?.status ?? .ok

            var responseData = Data()
            responseData.append(contentsOf: Array("HTTP/1.1 \(status.code) \(status.reasonPhrase)\r\n".utf8))

            for (name, value) in headers {
                responseData.append(contentsOf: Array("\(name): \(value)\r\n".utf8))
            }

            responseData.append(contentsOf: Array("\r\n".utf8))

            if let body, request.method != "HEAD" {
                responseData.append(body)
            }

            connection.send(
                content: responseData,
                completion: .contentProcessed { _ in }
            )
        }
    }
}

#endif
