//
// See LICENSE for this package's licensing information.
//

#if !canImport(NIOCore)

import RequestDLInternals

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

extension LocalServer {

    /// A minimal, hand-rolled HTTP/1.1 request reader: just enough of RFC 9112 for
    /// ``PortableConnection`` to answer what this test suite's own requests actually send
    /// (request line, headers, and a `Content-Length` or `Transfer-Encoding: chunked` body),
    /// standing in for what `NIOHTTP1`'s pipeline gives the NIO backend for free.
    struct PortableHTTPRequest: Sendable {
        let method: String
        let uri: String
        let headers: Internals.HTTPHeaders
        let body: Data

        /// Parses one request off the front of `buffer`, if it's complete. Returns `nil`
        /// (not an error) when `buffer` doesn't yet hold a full request: the caller owns
        /// deciding when to give up waiting for more bytes.
        static func parse(_ buffer: [UInt8]) throws -> (PortableHTTPRequest, Int)? {
            guard let headerEnd = firstRange(of: crlfcrlf, in: buffer) else {
                return nil
            }

            let headerText = String(decoding: buffer[..<headerEnd.lowerBound], as: UTF8.self)
            var lines = headerText.components(separatedBy: "\r\n")

            guard !lines.isEmpty else {
                throw LocalServer.PortableServerError.malformedRequest
            }

            let requestLine = lines.removeFirst()
            let requestLineParts = requestLine.split(separator: " ", omittingEmptySubsequences: true)

            guard requestLineParts.count >= 2 else {
                throw LocalServer.PortableServerError.malformedRequest
            }

            let method = String(requestLineParts[0])
            let uri = String(requestLineParts[1])

            var headers = Internals.HTTPHeaders()
            for line in lines where !line.isEmpty {
                guard let colon = line.firstIndex(of: ":") else {
                    continue
                }

                let name = String(line[line.startIndex..<colon]).trimmingWhitespace()
                let value = String(line[line.index(after: colon)...]).trimmingWhitespace()
                headers.add(name: name, value: value)
            }

            let bodyStart = headerEnd.upperBound

            let isChunked =
                headers.first(name: "Transfer-Encoding")?
                .lowercased()
                .contains("chunked") ?? false

            if isChunked {
                guard let (body, consumed) = try parseChunkedBody(buffer, from: bodyStart) else {
                    return nil
                }

                return (
                    PortableHTTPRequest(method: method, uri: uri, headers: headers, body: body),
                    consumed
                )
            }

            let contentLength = headers.first(name: "Content-Length").flatMap(Int.init) ?? 0
            let bodyEnd = bodyStart + contentLength

            guard buffer.count >= bodyEnd else {
                return nil
            }

            let body = Data(buffer[bodyStart..<bodyEnd])
            return (PortableHTTPRequest(method: method, uri: uri, headers: headers, body: body), bodyEnd)
        }

        // MARK: - Private static methods

        /// Reassembles a `Transfer-Encoding: chunked` body starting at `start`, per RFC 9112
        /// §7.1: a `<hex size>\r\n<size bytes>\r\n` sequence repeated until a zero-size chunk,
        /// followed by an (almost always empty, here) trailer section and a final blank line.
        private static func parseChunkedBody(_ buffer: [UInt8], from start: Int) throws -> (Data, Int)? {
            var offset = start
            var body = Data()

            while true {
                guard let sizeLineEnd = firstRange(of: crlf, in: buffer, from: offset) else {
                    return nil
                }

                let sizeLineText = String(decoding: buffer[offset..<sizeLineEnd.lowerBound], as: UTF8.self)
                let sizeHex = sizeLineText.split(separator: ";", maxSplits: 1).first.map(String.init) ?? sizeLineText

                guard let chunkSize = Int(sizeHex.trimmingWhitespace(), radix: 16) else {
                    throw LocalServer.PortableServerError.malformedRequest
                }

                let chunkStart = sizeLineEnd.upperBound

                if chunkSize == 0 {
                    if let trailerEnd = firstRange(of: crlfcrlf, in: buffer, from: chunkStart) {
                        return (body, trailerEnd.upperBound)
                    }

                    // The common case: no trailer headers, so the terminator is the bare
                    // `\r\n` right after the `0\r\n` size line, two bytes short of the
                    // `crlfcrlf` pattern above.
                    guard
                        buffer.count >= chunkStart + 2,
                        buffer[chunkStart] == crlf[0], buffer[chunkStart + 1] == crlf[1]
                    else {
                        return nil
                    }

                    return (body, chunkStart + 2)
                }

                let chunkEnd = chunkStart + chunkSize

                // `+ 2` for the CRLF every chunk's data is followed by, whether or not this is
                // the last one.
                guard buffer.count >= chunkEnd + 2 else {
                    return nil
                }

                body.append(contentsOf: buffer[chunkStart..<chunkEnd])
                offset = chunkEnd + 2
            }
        }

        /// The first index at which `pattern` occurs in `buffer`, searching from `start`.
        /// Written by hand, not `Collection.firstRange(of:)`, to stay independent of exactly
        /// which standard library version that API is available in.
        private static func firstRange(of pattern: [UInt8], in buffer: [UInt8], from start: Int = 0) -> Range<Int>? {
            guard !pattern.isEmpty, start >= 0, buffer.count - start >= pattern.count else {
                return nil
            }

            let lastPossibleStart = buffer.count - pattern.count
            var index = start

            while index <= lastPossibleStart {
                var matched = true

                for offset in 0..<pattern.count where buffer[index + offset] != pattern[offset] {
                    matched = false
                    break
                }

                if matched {
                    return index..<(index + pattern.count)
                }

                index += 1
            }

            return nil
        }
    }
}

private let crlf: [UInt8] = [0x0D, 0x0A]
private let crlfcrlf: [UInt8] = [0x0D, 0x0A, 0x0D, 0x0A]

extension String {

    fileprivate func trimmingWhitespace() -> String {
        var start = startIndex
        var end = endIndex

        while start < end, self[start] == " " || self[start] == "\t" {
            start = index(after: start)
        }

        while start < end {
            let before = index(before: end)
            guard self[before] == " " || self[before] == "\t" else {
                break
            }
            end = before
        }

        return String(self[start..<end])
    }
}

#endif
