/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct FormNode: PropertyNode {

    // MARK: - Internal properties

    let partLength: Int?
    let factory: @Sendable () -> PartFormRawValue

    // MARK: - Inits

    init(_ partLength: Int?, _ factory: @escaping @Sendable () -> PartFormRawValue) {
        self.partLength = partLength
        self.factory = factory
    }

    // MARK: - Internal methods

    func make(_ make: inout Make) async throws {
        let constructor = MultipartFormConstructor([factory()])

        make.request.headers.set(
            name: "Content-Type",
            value: "multipart/form-data; boundary=\"\(constructor.boundary)\""
        )

        make.request.body = Internals.Body(partLength, buffers: [
            Internals.DataBuffer(constructor.body)
        ])
    }
}
