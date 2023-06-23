/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct FormNode: PropertyNode {

    // MARK: - Internal properties

    let chunkSize: Int?
    let items: [FormItem]

    // MARK: - Inits

    init(
        chunkSize: Int?,
        item: FormItem
    ) {
        self.init(
            chunkSize: chunkSize,
            items: [item]
        )
    }

    init(
        chunkSize: Int?,
        items: [FormItem]
    ) {
        self.chunkSize = chunkSize
        self.items = items
    }

    // MARK: - Internal methods

    func make(_ make: inout Make) async throws {
        let constructor = FormGroupBuilder(items)

        make.request.headers.set(
            name: "Content-Type",
            value: "multipart/form-data; boundary=\"\(constructor.boundary)\""
        )

        let buffers = try constructor()

        let body = Internals.Body(
            chunkSize: chunkSize,
            buffers: buffers
        )

        if body.totalSize > .zero {
            make.request.headers.set(
                name: "Content-Length",
                value: String(body.totalSize)
            )
        }

        make.request.body = body
    }
}
