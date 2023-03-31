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

        make.request.setValue(
            "multipart/form-data; boundary=\"\(constructor.boundary)\"",
            forHTTPHeaderField: "Content-Type"
        )

        make.request.httpBody = constructor.body
    }
}
