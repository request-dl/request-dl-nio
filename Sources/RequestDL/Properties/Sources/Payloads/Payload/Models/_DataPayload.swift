/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public struct _DataPayload: PayloadProvider {

    // MARK: - Internal properties

    var buffer: Internals.AnyBuffer {
        Internals.DataBuffer(data)
    }

    // MARK: - Private properties

    private let data: Data

    // MARK: - Inits

    init(_ data: Data) {
        self.data = data
    }
}
