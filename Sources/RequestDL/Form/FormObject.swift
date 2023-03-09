/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct FormObject: NodeObject {

    let factory: () -> PartFormRawValue

    init(_ factory: @escaping () -> PartFormRawValue) {
        self.factory = factory
    }

    func makeProperty(_ make: Make) {
        let constructor = MultipartFormConstructor([factory()])

        make.request.setValue(
            "multipart/form-data; boundary=\"\(constructor.boundary)\"",
            forHTTPHeaderField: "Content-Type"
        )

        make.request.httpBody = constructor.body
    }
}
