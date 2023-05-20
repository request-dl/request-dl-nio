/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct DataPayloadFactory: PayloadFactory {

    // MARK: - Internal properties

    let data: Data
    let contentType: ContentType

    // MARK: - Inits

    init(
        data: Data,
        contentType: ContentType
    ) {
        self.data = data
        self.contentType = contentType
    }

    // MARK: - Internal methods

    func callAsFunction(_ input: PayloadInput) throws -> PayloadOutput {
        .init(
            contentType: contentType,
            source: .buffer(Internals.DataBuffer(data))
        )
    }
}
