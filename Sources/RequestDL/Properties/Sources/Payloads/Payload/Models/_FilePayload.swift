/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public struct _FilePayload: PayloadProvider {

    private let file: URL

    init(_ file: URL) {
        self.file = file
    }

    var buffer: Internals.FileBuffer {
        Internals.FileBuffer(file)
    }
}
