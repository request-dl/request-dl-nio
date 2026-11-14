//
// See LICENSE for this package's licensing information.
//

extension Internals {

    /// Thrown when a `TrustRoots` configuration, which *replaces* the system's trusted roots,
    /// leaves not a single usable certificate to anchor trust on.
    ///
    /// Handing the evaluator an empty anchor list makes it skip anchoring altogether, so the
    /// system trust store would silently become the anchor: the opposite of what replacing it
    /// asked for. Failing here keeps the exclusive set exclusive.
    package struct EmptyTrustRootsError: Swift.Error, CustomStringConvertible, Sendable {
        package var description: String {
            "Invalid trust roots: TrustRoots replaces the system's trusted roots, but none of its certificates could be loaded, so no server certificate could ever be trusted. Check that the file or bytes contain at least one valid PEM certificate."
        }

        package init() {}
    }
}
