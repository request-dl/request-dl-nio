//
// See LICENSE for this package's licensing information.
//

#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import UIKit

extension Image {

    /// Wraps a decoded ``PlatformImage``, reinterpreting it at `scale` when it differs from the
    /// image's own.
    ///
    /// Rewrapping the existing `CGImage` at a new scale is cheap — no re-decoding of the
    /// original data — which is what makes it worth doing here instead of threading `scale`
    /// through ``RDLImageLoader`` decoding: the loader dedupes concurrent loads of the same `id`
    /// into a single decoded image shared by every caller, and callers are free to ask for
    /// different scales.
    init(platformImage: PlatformImage, scale: CGFloat) {
        guard scale != platformImage.scale, let cgImage = platformImage.cgImage else {
            self.init(uiImage: platformImage)
            return
        }

        self.init(
            uiImage: UIImage(
                cgImage: cgImage,
                scale: scale,
                orientation: platformImage.imageOrientation
            )
        )
    }
}

#elseif canImport(SwiftUI) && canImport(AppKit)
import AppKit
import SwiftUI

extension Image {

    /// Wraps a decoded ``PlatformImage``.
    ///
    /// - Note: `scale` has no effect on macOS: `NSImage` doesn't model resolution the way
    /// `UIImage` does, so there's nothing to reinterpret it against.
    init(platformImage: PlatformImage, scale: CGFloat) {
        self.init(nsImage: platformImage)
    }
}

#endif
