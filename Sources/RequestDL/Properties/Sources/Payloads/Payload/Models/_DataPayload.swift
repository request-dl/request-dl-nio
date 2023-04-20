/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public struct _DataPayload: PayloadProvider {

    private let data: Data

    init(_ data: Data) {
        self.data = data
    }

    var buffer: Internals.DataBuffer {
        Internals.DataBuffer(data)
    }
}
