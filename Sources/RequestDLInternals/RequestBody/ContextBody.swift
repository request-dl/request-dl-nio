/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public class _ContextBody {

    private(set) var buffers: [BufferProtocol] = []

    func append(_ buffer: BufferProtocol) {
        buffers.append(buffer)
    }
}
