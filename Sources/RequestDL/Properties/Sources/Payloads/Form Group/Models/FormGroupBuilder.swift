/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct FormGroupBuilder: Sendable {

    // MARK: - Private static properties

    private static var boundary: String {
        let prefix = UInt64.random(in: .min ... .max)
        let sufix = UInt64.random(in: .min ... .max)

        return "\(String(prefix, radix: 16)):\(String(sufix, radix: 16))"
    }

    // MARK: - Internal properties

    var eol: Character {
        "\r\n"
    }

    let boundary: String
    let items: [FormItem]

    // MARK: - Inits

    init(_ items: [FormItem]) {
        self.init(Self.boundary, items: items)
    }

    fileprivate init(_ boundary: String, items: [FormItem]) {
        self.boundary = boundary
        self.items = items
    }

    // MARK: - Internal methods

    func callAsFunction() -> [Internals.AnyBuffer] {
        var buffers = [Internals.AnyBuffer]()

        for item in items {
            var nodeBuffers = [Internals.AnyBuffer]()

            nodeBuffers.append(Internals.DataBuffer("--\(boundary)\(eol)".utf8))
            nodeBuffers.append(contentsOf: buildBuffer(item))
            nodeBuffers.append(Internals.DataBuffer(eol.utf8))

            buffers.append(contentsOf: nodeBuffers)
        }

        buffers.append(Internals.DataBuffer("--\(boundary)--".utf8))
        buffers.append(Internals.DataBuffer("\(eol)".utf8))

        return buffers
    }

    // MARK: - Private methods

    private func buildBuffer(_ item: FormItem) -> [Internals.AnyBuffer] {
         [
            buildHeadersBuffer(item.headers()),
            item.buffer
        ]
    }

    private func buildHeadersBuffer(_ headers: HTTPHeaders) -> Internals.AnyBuffer {
        var buffer = Internals.DataBuffer()

        for (name, value) in headers {
            buffer.writeBytes((name + ": " + value).utf8)
            buffer.writeBytes(eol.utf8)
        }

        buffer.writeBytes(eol.utf8)
        return buffer
    }
}
