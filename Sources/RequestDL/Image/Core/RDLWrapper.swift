//
// See LICENSE for this package's licensing information.
//

#if canImport(UIKit) || canImport(AppKit)

/// A namespace that exposes RequestDL's image loading APIs without adding members directly to
/// the wrapped type, e.g. `imageView.rdl.setImage(with: url)`.
public struct RDLWrapper<Base: AnyObject> {

    /// The wrapped instance.
    public let base: Base

    init(_ base: Base) {
        self.base = base
    }
}

/// A type that exposes RequestDL's image loading APIs through its `rdl` property.
///
/// Conform `UIImageView`, `NSImageView` and `WKInterfaceImage` to this protocol to make
/// `someView.rdl.setImage(...)` available on them.
public protocol RDLCompatible: AnyObject {}

extension RDLCompatible {

    /// A namespace for RequestDL's image loading APIs, e.g. `imageView.rdl.setImage(with: url)`.
    public var rdl: RDLWrapper<Self> {
        RDLWrapper(self)
    }
}

#endif
