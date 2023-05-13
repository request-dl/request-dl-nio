/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public struct _EncodablePayload<Object: Encodable>: PayloadProvider, @unchecked Sendable {

    // MARK: - Internal properties

    var buffer: Internals.DataBuffer {
        Internals.DataBuffer(data)
    }

    // MARK: - Private properties

    private let object: Object
    private let encoder: JSONEncoder

    private var data: Data {
        do {
            return try encoder.encode(object)
        } catch {
            Internals.Log.failure(
                .cantEncodeObject(object, error)
            )
        }
    }

    // MARK: - Inits

    init(
        _ object: Object,
        encoder: JSONEncoder = .init()
    ) {
        self.object = object
        self.encoder = encoder
    }
}
