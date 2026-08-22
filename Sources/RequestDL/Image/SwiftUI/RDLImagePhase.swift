//
// See LICENSE for this package's licensing information.
//

#if canImport(SwiftUI) && (canImport(UIKit) || canImport(AppKit))
import SwiftUI

/// The current phase of an ``RDLImage``'s asynchronous load.
public enum RDLImagePhase {

    /// No image has loaded yet, either because the load hasn't started, is still in flight, or
    /// there is no request to run.
    case empty

    /// An image finished loading successfully.
    case success(Image)

    /// The load finished with an error.
    case failure(Error)

    /// The loaded image, if the phase is ``success(_:)``.
    public var image: Image? {
        guard case .success(let image) = self else {
            return nil
        }

        return image
    }

    /// The error that ended the load, if the phase is ``failure(_:)``.
    public var error: Error? {
        guard case .failure(let error) = self else {
            return nil
        }

        return error
    }
}

#endif
