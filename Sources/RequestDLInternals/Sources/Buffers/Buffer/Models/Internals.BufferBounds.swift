//
// See LICENSE for this package's licensing information.
//

extension Internals {

    /// The arithmetic that keeps a buffer's `Int` indices honest against the `UInt64` offsets its
    /// streams speak.
    ///
    /// A stream addresses a resource with a `UInt64`, and a ``Buffer`` keeps its cursors in `Int`.
    /// Where `Int` is 64 bits the two never disagree in practice. Where it is 32 bits (watchOS
    /// `arm64_32`) a resource past 2 GiB is perfectly addressable by the stream and not by the
    /// buffer, and converting an offset past `Int.max` traps.
    package enum BufferBounds {

        /// The offset right after `count` bytes written at `index`, or `nil` when it does not fit in
        /// `Index`.
        ///
        /// What a store asks *before* writing, because a write that lands cannot be taken back: the
        /// bytes would be in the resource and the cursor that should account for them could not
        /// say so. Refusing up front leaves both where they were, which is what a failed write
        /// already does everywhere in ``Buffer``.
        ///
        /// Generic over the index so a test can run the 32 bit boundary with `Int32` on a 64 bit
        /// machine. Production code always passes `Int.self`.
        package static func end<Index: FixedWidthInteger & SignedInteger>(
            ofWritingAt index: UInt64,
            count: Int,
            as _: Index.Type
        ) -> Index? {
            guard
                count >= .zero,
                let start = Index(exactly: index),
                let length = Index(exactly: count),
                length <= Index.max - start
            else {
                return nil
            }

            return start + length
        }
    }
}
