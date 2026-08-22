//
// See LICENSE for this package's licensing information.
//

#if canImport(UIKit)
import UIKit

/// The platform-native image type used by RequestDL's image loading APIs.
///
/// Resolves to `UIImage` on iOS, tvOS and watchOS, and to `NSImage` on macOS.
public typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit

/// The platform-native image type used by RequestDL's image loading APIs.
///
/// Resolves to `UIImage` on iOS, tvOS and watchOS, and to `NSImage` on macOS.
public typealias PlatformImage = NSImage
#endif

#if canImport(UIKit) || canImport(AppKit)

/// A `Sendable` box around ``PlatformImage``.
///
/// `UIImage`/`NSImage` are reference types that predate Swift concurrency and are not marked
/// `Sendable`, even though handing a fully-initialized instance across an isolation boundary is
/// safe in practice: nothing here mutates it after decoding. The box exists only to satisfy the
/// compiler at that single crossing point.
struct SendableImage: @unchecked Sendable {

    let image: PlatformImage

    init(_ image: PlatformImage) {
        self.image = image
    }
}

#endif
