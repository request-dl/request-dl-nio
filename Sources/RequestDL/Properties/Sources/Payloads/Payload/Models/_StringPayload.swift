/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public struct _StringPayload: PayloadProvider {

    // MARK: - Internal properties

    var buffer: Internals.DataBuffer {
        Internals.DataBuffer(data)
    }

    // MARK: - Private properties

    private var data: Data {
        if let data = string.data(using: encoding) {
            return data
        }

        Internals.Log.failure(
            .cantEncodeString(
                string,
                encoding
            )
        )
    }

    private let string: String
    private let encoding: String.Encoding

    // MARK: - Inits

    init(
        _ string: String,
        using encoding: String.Encoding
    ) {
        self.string = string
        self.encoding = encoding
    }
}
