/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct PayloadNode: PropertyNode {

    // MARK: - Internal properties

    let factory: PayloadFactory
    let charset: Charset
    let urlEncoder: URLEncoder
    let chunkSize: Int?

    // MARK: - Internal methods

    func make(_ make: inout Make) async throws {
        let input = PayloadInput(
            method: make.requestConfiguration.method,
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

            guard ![nil, "GET", "HEAD"].contains(make.requestConfiguration.method) else {
                removeAnySetHeaders(&make.requestConfiguration.headers)
                make.requestConfiguration.queries.append(contentsOf: queries)
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
        make.requestConfiguration.headers.set(
            name: "Content-Type",
            value: String(output.contentType)
        )

        let body = RequestBody(
            chunkSize: chunkSize,
            buffers: [buffer]
        )

        if body.totalSize > .zero {
            make.requestConfiguration.headers.set(
                name: "Content-Length",
                value: String(body.totalSize)
            )
        } else {
            make.requestConfiguration.headers.remove(name: "Content-Length")
        }

        make.requestConfiguration.body = body
    }

    private func removeAnySetHeaders(_ headers: inout HTTPHeaders) {
        headers.remove(name: "Content-Type")
        headers.remove(name: "Content-Length")
    }
}
