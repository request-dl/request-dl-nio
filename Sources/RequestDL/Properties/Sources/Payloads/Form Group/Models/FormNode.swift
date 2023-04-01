/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct FormNode: PropertyNode {

    let factory: () -> PartFormRawValue

    init(_ factory: @escaping () -> PartFormRawValue) {
        self.factory = factory
    }

    func make(_ make: inout Make) async throws {
        let constructor = MultipartFormConstructor([factory()])

        make.request.headers.setValue(
            "multipart/form-data; boundary=\"\(constructor.boundary)\"",
            forKey: "Content-Type"
        )

        make.request.body = Internals.Body(buffers: [
            Internals.DataBuffer(constructor.body)
        ])
    }
}
