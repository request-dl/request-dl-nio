//
// See LICENSE for this package's licensing information.
//

// The hand-rolled HTTP/1.1 half of `LocalServer.PortableServer.swift`: there is no
// Network.framework equivalent of NIOHTTP1's `configureHTTPServerPipeline()` to build this on top
// of instead, so this parses request framing (headers, `Content-Length` or
// `Transfer-Encoding: chunked` bodies, keep-alive) directly off the plaintext bytes
// `NWConnection.receive` hands back once its own TLS layer has already decrypted them.
#if !canImport(NIOCore)

import Network

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension LocalServer.PortableServer {

    /// One accepted `NWConnection`. `@unchecked Sendable` for the same reason the NIOCore side's
    /// `HTTPHandler` is: every `receive`/`send` completion for one connection runs serially on
    /// this connection's own `queue`, so `buffer`/`isFinished` are never actually touched
    /// concurrently, even though the compiler can't see that guarantee through the escaping
    /// completion closures.
    final class Connection: @unchecked Sendable {

        struct RequestHead {
            let method: String
            let uri: String
            let headers: [(name: String, value: String)]
            let keepAlive: Bool
        }

        // MARK: - Private properties

        private let connection: NWConnection
        private let queue: DispatchQueue
        private let responseQueue: LocalServer.ResponseQueue
        private let onClose: (Connection) -> Void

        private var buffer: [UInt8] = []
        private var isFinished = false

        // MARK: - Inits

        init(
            connection: NWConnection,
            queue: DispatchQueue,
            responseQueue: LocalServer.ResponseQueue,
            onClose: @escaping (Connection) -> Void
        ) {
            self.connection = connection
            self.queue = queue
            self.responseQueue = responseQueue
            self.onClose = onClose
        }

        // MARK: - Internal methods

        func start() {
            connection.stateUpdateHandler = { [weak self] state in
                switch state {
                case .failed, .cancelled:
                    self?.finish()
                default:
                    break
                }
            }

            connection.start(queue: queue)
            receiveMore()
        }

        func cancel() {
            connection.cancel()
        }

        // MARK: - Private methods

        private func finish() {
            guard !isFinished else { return }
            isFinished = true
            onClose(self)
        }

        private func receiveMore() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
                guard let self else { return }

                if let data, !data.isEmpty {
                    self.buffer.append(contentsOf: data)
                    self.processBuffer()
                }

                if error != nil || isComplete || self.isFinished {
                    self.finish()
                    return
                }

                self.receiveMore()
            }
        }

        /// Drains as many complete, pipelined/keep-alive requests as `buffer` already holds,
        /// mirroring the NIOCore side's per-request `HTTPHandler` reset (there: `cleanup()`
        /// between requests; here: simply re-entering this loop with what is left of `buffer`).
        private func processBuffer() {
            while !isFinished, let parsed = Self.parseRequest(from: buffer) {
                buffer.removeFirst(parsed.consumed)
                respond(to: parsed.head, receivedBytes: parsed.body.count, body: parsed.body)

                if !parsed.head.keepAlive {
                    cancel()
                    break
                }
            }
        }

        private func respond(to head: RequestHead, receivedBytes: Int, body: Data) {
            let configuration = responseQueue.popLast(at: head.uri)

            let cookieHeader = head.headers.first {
                $0.name.caseInsensitiveCompare("Cookie") == .orderedSame
            }?.value

            let userAgentHeader = head.headers.first {
                $0.name.caseInsensitiveCompare("User-Agent") == .orderedSame
            }?.value

            let responseBody = LocalServer.makeResponseBody(
                configuredData: configuration?.data,
                receivedBytes: receivedBytes,
                cookieHeader: cookieHeader,
                userAgentHeader: userAgentHeader
            )

            let status = configuration?.status ?? .ok
            var headerLines = ""

            if let configuration {
                // Content-Length is always set below from the actual encoded body, same as the
                // NIOCore side's `headers.replaceOrAdd(name: "Content-Length", ...)`: any
                // configured value would otherwise disagree with what is actually sent.
                for (name, value) in configuration.headers
                where name.caseInsensitiveCompare("Content-Length") != .orderedSame {
                    headerLines += "\(name): \(value)\r\n"
                }
            }

            headerLines += "Content-Length: \(responseBody?.count ?? 0)\r\n"

            var responseData = Data("HTTP/1.1 \(status.code) \(status.reasonPhrase)\r\n\(headerLines)\r\n".utf8)

            if head.method != "HEAD", let responseBody {
                responseData.append(responseBody)
            }

            connection.send(
                content: responseData,
                completion: .contentProcessed { [weak self] error in
                    if error != nil {
                        self?.finish()
                    }
                }
            )
        }
    }
}

// MARK: - Hand-rolled HTTP/1.1 parsing

extension LocalServer.PortableServer.Connection {

    private static let crlf: [UInt8] = [0x0D, 0x0A]
    private static let doubleCRLF: [UInt8] = [0x0D, 0x0A, 0x0D, 0x0A]

    /// Parses exactly one HTTP/1.1 request off the front of `bytes`, if a complete one is present
    /// yet. Returns `nil` when more data is needed, never a partial result: `processBuffer()`
    /// loops on this to drain as many pipelined/keep-alive requests as `bytes` already holds.
    fileprivate static func parseRequest(
        from bytes: [UInt8]
    ) -> (head: RequestHead, body: Data, consumed: Int)? {
        guard let headerEnd = find(doubleCRLF, in: bytes, from: 0) else { return nil }

        guard let headerString = String(bytes: bytes[0..<headerEnd], encoding: .utf8) else {
            return nil
        }

        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }

        let requestComponents = requestLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard requestComponents.count >= 2 else { return nil }

        let method = String(requestComponents[0])
        let uri = String(requestComponents[1])
        let httpVersion = requestComponents.count > 2 ? String(requestComponents[2]) : "HTTP/1.1"

        var headers: [(name: String, value: String)] = []
        for line in lines.dropFirst() where !line.isEmpty {
            guard let colonIndex = line.firstIndex(of: ":") else { continue }
            headers.append(
                (
                    name: String(line[line.startIndex..<colonIndex]).trimmingCharacters(in: .whitespaces),
                    value: String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                )
            )
        }

        let bodyStart = headerEnd + doubleCRLF.count
        let keepAlive = defaultKeepAlive(version: httpVersion, headers: headers)
        let head = RequestHead(method: method, uri: uri, headers: headers, keepAlive: keepAlive)

        let isChunked = headers.contains {
            $0.name.caseInsensitiveCompare("Transfer-Encoding") == .orderedSame
                && $0.value.lowercased().contains("chunked")
        }

        if isChunked {
            guard let (body, consumed) = decodeChunkedBody(bytes: bytes, from: bodyStart) else {
                return nil
            }
            return (head, body, consumed)
        }

        let contentLength =
            headers
            .first { $0.name.caseInsensitiveCompare("Content-Length") == .orderedSame }
            .flatMap { Int($0.value) } ?? 0

        guard bytes.count >= bodyStart + contentLength else { return nil }

        let body = Data(bytes[bodyStart..<(bodyStart + contentLength)])
        return (head, body, bodyStart + contentLength)
    }

    /// No trailer-header support: nothing in this package's own chunked-transfer client
    /// (`RequestBody`'s compression fallback, the only source of a chunked request this server
    /// ever sees) sends any, so the message is assumed to end with the plain terminating CRLF
    /// right after the zero-length chunk.
    private static func decodeChunkedBody(bytes: [UInt8], from start: Int) -> (Data, Int)? {
        var offset = start
        var result = [UInt8]()

        while true {
            guard let lineEnd = find(crlf, in: bytes, from: offset) else { return nil }
            guard let sizeLine = String(bytes: bytes[offset..<lineEnd], encoding: .utf8) else { return nil }

            let sizeHex = sizeLine.split(separator: ";", maxSplits: 1).first.map(String.init) ?? sizeLine
            guard let chunkSize = Int(sizeHex.trimmingCharacters(in: .whitespaces), radix: 16) else {
                return nil
            }

            let chunkStart = lineEnd + crlf.count

            if chunkSize == 0 {
                guard bytes.count >= chunkStart + crlf.count else { return nil }
                return (Data(result), chunkStart + crlf.count)
            }

            let chunkEnd = chunkStart + chunkSize
            guard bytes.count >= chunkEnd + crlf.count else { return nil }

            result.append(contentsOf: bytes[chunkStart..<chunkEnd])
            offset = chunkEnd + crlf.count
        }
    }

    private static func defaultKeepAlive(version: String, headers: [(name: String, value: String)]) -> Bool {
        let connectionHeader = headers.first {
            $0.name.caseInsensitiveCompare("Connection") == .orderedSame
        }?.value.lowercased()

        if let connectionHeader {
            if connectionHeader.contains("close") { return false }
            if connectionHeader.contains("keep-alive") { return true }
        }

        return version.uppercased() != "HTTP/1.0"
    }

    /// Naive substring search over a small in-memory buffer: fine for one HTTP request's worth
    /// of headers, not meant for anything larger.
    private static func find(_ pattern: [UInt8], in bytes: [UInt8], from start: Int) -> Int? {
        guard start >= 0, bytes.count >= pattern.count else { return nil }
        let upperBound = bytes.count - pattern.count
        guard upperBound >= start else { return nil }

        for index in start...upperBound {
            var matched = true
            for offset in 0..<pattern.count where bytes[index + offset] != pattern[offset] {
                matched = false
                break
            }
            if matched { return index }
        }
        return nil
    }
}

#endif
