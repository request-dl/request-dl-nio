/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct PayloadNode: PropertyNode {

    // MARK: - Internal properties

    let factory: PayloadFactory
    let charset: Charset
    let urlEncoder: URLEncoder
    let partLength: Int?

    // MARK: - Internal methods

    func make(_ make: inout Make) async throws {
        let input = PayloadInput(
            method: make.request.method,
            charset: charset,
            urlEncoder: urlEncoder
        )

        let output = try factory(input)

        switch output.source {
        case .buffer(let buffer):
            setBodyWithBuffer(
                buffer: buffer,
                output: output,
                make: &make
            )

        case .urlEncoded(let queries):
            let queries = queries.map { $0.build() }

            guard !["GET", "HEAD"].contains(make.request.method) else {
                make.request.queries.append(contentsOf: queries)
                return
            }

            let buffer = try Internals.DataBuffer(
                input.charset.encode(queries.joined())
            )

            setBodyWithBuffer(
                buffer: buffer,
                output: output,
                make: &make
            )
        }
    }

    // MARK: - Private methods

    private func setBodyWithBuffer(
        buffer: Internals.AnyBuffer,
        output: PayloadOutput,
        make: inout Make
    ) {
        make.request.headers.set(
            name: "Content-Type",
            value: String(output.contentType)
        )

        make.request.headers.set(
            name: "Content-Length",
            value: String(buffer.estimatedBytes)
        )

        make.request.body = Internals.Body(partLength, buffers: [buffer])
    }
}
