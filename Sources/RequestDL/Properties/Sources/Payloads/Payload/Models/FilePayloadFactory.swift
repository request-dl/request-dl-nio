/*
 See LICENSE for this package's licensing information.
*/

#if canImport(Darwin)
import Foundation
#else
@preconcurrency import Foundation
#endif

struct FilePayloadFactory: PayloadFactory {

    // MARK: - Internal properties

    let url: URL
    let contentType: ContentType

    // MARK: - Inits

    init(url: URL, contentType: ContentType) {
        self.url = url
        self.contentType = contentType
    }

    // MARK: - Internal methods

    func callAsFunction(_ input: PayloadInput) throws -> PayloadOutput {
        .init(
            contentType: contentType,
            source: .buffer(Internals.FileBuffer(url))
        )
    }
}
