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

    private var data: Data {
        do {
            return try encoder.encode(object)
        } catch {
            Internals.Log.failure(
                .cantEncodeObject(object, error)
            )
        }
    }

    var buffer: Internals.DataBuffer {
        Internals.DataBuffer(data)
    }
}
