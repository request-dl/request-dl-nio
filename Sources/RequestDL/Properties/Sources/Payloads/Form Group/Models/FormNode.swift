/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct FormNode: PropertyNode {

    // MARK: - Internal properties

    let partLength: Int?
    let factory: @Sendable () -> MultipartItem

    // MARK: - Inits

    init(_ partLength: Int?, _ factory: @escaping @Sendable () -> MultipartItem) {
        self.partLength = partLength
        self.factory = factory
    }

    // MARK: - Internal methods

    func make(_ make: inout Make) async throws {
        let constructor = MultipartBuilder([factory()])

        make.request.headers.set(
            name: "Content-Type",
            value: "multipart/form-data; boundary=\"\(constructor.boundary)\""
        )

        make.request.body = Internals.Body(partLength, buffers: constructor())
    }
}
