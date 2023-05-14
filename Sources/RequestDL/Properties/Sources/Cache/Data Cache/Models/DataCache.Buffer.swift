/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension DataCache {

    struct Buffer: Sendable {

        // MARK: - Private properties

        private var memoryBuffer: Internals.AnyBuffer?
        private var diskBuffer: Internals.AnyBuffer?

        // MARK: - Inits

        init(
            memoryBuffer: Internals.AnyBuffer?,
            diskBuffer: Internals.AnyBuffer?
        ) {
            self.memoryBuffer = memoryBuffer
            self.diskBuffer = diskBuffer
        }

        // MARK: - Internal methods

        mutating func writeBuffer(_ buffer: Internals.AnyBuffer) {
            guard let bytes = buffer.getBytes() else {
                return
            }

            memoryBuffer?.writeBytes(bytes)
            diskBuffer?.writeBytes(bytes)
        }
    }
}
