//
// See LICENSE for this package's licensing information.
//

extension Internals {

    /// Namespace for the traps and signals a test needs to intercept.
    ///
    /// Every member routes through a task local closure in `DEBUG` and straight to the standard
    /// library outside it, so a release build carries neither the indirection nor the storage.
    enum Override {}
}
