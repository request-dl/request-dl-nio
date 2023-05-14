/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public struct _EncodablePayload<Object: Encodable>: PayloadProvider, @unchecked Sendable {

    // MARK: - Internal properties

    var buffer: Internals.AnyBuffer {
        Internals.DataBuffer(data)
    }

    // MARK: - Private properties

    private var data: Data {
        do {
            return try encoder.encode(object)
        } catch {
            Internals.Log.failure(
                .cantEncodeObject(object, error)
            )
        }
    }

    private let object: Object
    private let encoder: JSONEncoder

    // MARK: - Inits

    init(
        _ object: Object,
        encoder: JSONEncoder = .init()
    ) {
        self.object = object
        self.encoder = encoder
    }
}
