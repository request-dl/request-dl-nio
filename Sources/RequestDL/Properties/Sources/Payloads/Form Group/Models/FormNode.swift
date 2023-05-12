/*
 See LICENSE for this package's licensing information.
*/

import Foundation

@RequestActor
struct FormNode: PropertyNode {

    let partLength: Int?
    let factory: () -> PartFormRawValue

    init(_ partLength: Int?, _ factory: @escaping () -> PartFormRawValue) {
        self.partLength = partLength
        self.factory = factory
    }

    func make(_ make: inout Make) async throws {
        let constructor = MultipartFormConstructor([factory()])

        make.request.headers.setValue(
            "multipart/form-data; boundary=\"\(constructor.boundary)\"",
            forKey: "Content-Type"
        )

        make.request.body = Internals.Body(partLength, buffers: [
            Internals.DataBuffer(constructor.body)
        ])
    }
}
