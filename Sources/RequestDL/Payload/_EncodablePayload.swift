/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public struct _EncodablePayload<Object: Encodable>: PayloadProvider {

    private let object: Object
    private let encoder: JSONEncoder

    init(
        _ object: Object,
        encoder: JSONEncoder = .init()
    ) {
        self.object = object
        self.encoder = encoder
    }

    public var data: Data {
        do {
            return try encoder.encode(object)
        } catch {
            fatalError(
                """
                An error occurred while trying to encode the object to data: \(error.localizedDescription).
                """
            )
        }
    }
}
