/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public struct _StringPayload: PayloadProvider {

    private let string: String
    private let encoding: String.Encoding

    init(
        _ string: String,
        using encoding: String.Encoding
    ) {
        self.string = string
        self.encoding = encoding
    }

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

    var buffer: Internals.DataBuffer {
        Internals.DataBuffer(data)
    }
}
