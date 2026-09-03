//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

struct FormNode: PropertyNode {

    // MARK: - Internal properties

    let chunkSize: Int?
    let items: [FormItem]

    /// Captured from `inputs.environment.descriptorFormFields` at `_makeProperty` time by
    /// whichever `Property` builds this node (`Form`, `FormGroup`) -- not read from inside
    /// `make()` itself, since `PropertyNode.make(_:)` has no `environment` of its own to read.
    let descriptorFormFields: DescriptorFormFieldBox?

    // MARK: - Inits

    init(
        chunkSize: Int?,
        item: FormItem,
        descriptorFormFields: DescriptorFormFieldBox?
    ) {
        self.init(
            chunkSize: chunkSize,
            items: [item],
            descriptorFormFields: descriptorFormFields
        )
    }

    init(
        chunkSize: Int?,
        items: [FormItem],
        descriptorFormFields: DescriptorFormFieldBox?
    ) {
        self.chunkSize = chunkSize
        self.items = items
        self.descriptorFormFields = descriptorFormFields
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

        // Each item's factory runs exactly once here, however many things below need its
        // output — `FormGroupBuilder` used to run it again itself, once per item, for every
        // request; a `TaskDescriptor` pass needing the same output no longer means running it a
        // third time between the two.
        var outputs: [FormItem.Output] = []
        outputs.reserveCapacity(items.count)

        for item in items {
            outputs.append(try await item())
        }

        // A `TaskDescriptor` pass (see `RawTask.description(_:)`) needs every field's own
        // name/filename/content-type/bytes — still right here, one item at a time — before
        // `constructor()` below flattens everything into one multipart byte stream with a
        // boundary, at which point that structure is gone.
        if let descriptorFormFields {
            for output in outputs {
                descriptorFormFields.fields.append(
                    FormFieldDescriptor(
                        name: output.name,
                        filename: output.filename,
                        contentType: output.headers.first(name: "Content-Type") ?? "",
                        content: await output.buffer.getData() ?? Data()
                    )
                )
            }
        }

        let constructor = FormGroupBuilder(outputs)

        make.requestConfiguration.headers.set(
            name: "Content-Type",
            value: "multipart/form-data; boundary=\"\(constructor.boundary)\""
        )

        let buffers = await constructor()

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
