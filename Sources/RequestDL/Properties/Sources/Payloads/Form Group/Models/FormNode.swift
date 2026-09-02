//
// See LICENSE for this package's licensing information.
//

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
        guard !items.isEmpty else {
            removeAnySetHeaders(&make.requestConfiguration.headers)
            return
        }

        // See `PayloadNode.setBodyWithBuffer`'s identical guard for why: a body attached to a
        // request whose method is otherwise left to default to `"GET"` fails outright on
        // `.urlSession`. Only fills in a default, never overrides an explicit `RequestMethod`.
        if make.requestConfiguration.method == nil {
            make.requestConfiguration.method = "POST"
        }

        let constructor = FormGroupBuilder(items)

        make.requestConfiguration.headers.set(
            name: "Content-Type",
            value: "multipart/form-data; boundary=\"\(constructor.boundary)\""
        )

        let buffers = try await constructor()

        let body = RequestBody(
            chunkSize: chunkSize,
            buffers: buffers
        )

        make.requestConfiguration.headers.set(
            name: "Content-Length",
            value: String(body.totalSize)
        )

        make.requestConfiguration.body = body
    }

    // MARK: - Private methods

    private func removeAnySetHeaders(_ headers: inout HTTPHeaders) {
        headers.remove(name: "Content-Type")
        headers.remove(name: "Content-Length")
    }
}
