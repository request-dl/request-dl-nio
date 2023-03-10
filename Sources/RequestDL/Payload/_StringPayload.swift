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

    public var data: Data {
        string.data(using: encoding) ?? Data()
    }
}
