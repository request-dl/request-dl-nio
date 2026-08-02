//
// See LICENSE for this package's licensing information.
//

extension DataCache {

    struct Buffer: Sendable {

        var readableBytes: Int {
            (memoryBuffer ?? diskBuffer)?.readableBytes ?? .zero
        }

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

        mutating func writeBuffer(_ buffer: Internals.AnyBuffer) async {
            guard let bytes = await buffer.getBytes() else {
                return
            }

            await memoryBuffer?.writeBytes(bytes)
            await diskBuffer?.writeBytes(bytes)
        }
    }
}
