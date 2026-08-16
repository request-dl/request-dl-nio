//
// See LICENSE for this package's licensing information.
//

extension Array {

    /// Drains an `AsyncSequence` into an array.
    ///
    /// - Note: The generic parameter is deliberately not called `Sequence`. That shadows
    /// `Swift.Sequence` for the whole declaration, and any constraint written against the
    /// standard library protocol inside it silently means something else.
    package init<Source: AsyncSequence>(_ sequence: Source) async throws where Element == Source.Element {
        self.init()

        for try await element in sequence {
            append(element)
        }
    }
}
