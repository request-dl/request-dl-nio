/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public struct _FilePayload: PayloadProvider {

    // MARK: - Internal properties

    var buffer: Internals.AnyBuffer {
        Internals.FileBuffer(file)
    }

    // MARK: - Private properties

    private let file: URL

    // MARK: - Inits

    init(_ file: URL) {
        self.file = file
    }
}
