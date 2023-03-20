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

        make.request.headers.setValue(
            "multipart/form-data; boundary=\"\(constructor.boundary)\"",
            forKey: "Content-Type"
        )

        let data = constructor.body

        make.request.body = .init(length: data.count, streams: [{
            InputStream(data: data)
        }])
    }
}
