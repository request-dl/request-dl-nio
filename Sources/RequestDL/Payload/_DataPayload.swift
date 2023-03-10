/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public struct _DataPayload: PayloadProvider {

    public let data: Data

    init(_ data: Data) {
        self.data = data
    }
}
