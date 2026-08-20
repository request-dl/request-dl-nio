//
// See LICENSE for this package's licensing information.
//

#if canImport(UIKit) && !os(watchOS)
import UIKit

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.URL
import struct Foundation.Data
#endif

/// Backs the in-flight load tracked on each `UIImageView`, via the standard Swift
/// associated-object pattern: only this variable's stable address is ever used, its value is
/// never read or written, so `nonisolated(unsafe)` is safe.
private nonisolated(unsafe) var rdlLoadTaskKey: UInt8 = 0

extension UIImageView: RDLCompatible {}

extension RDLWrapper where Base: UIImageView {

    /// The in-flight load started by `setImage`, if any.
    ///
    /// Reading and writing this is what makes reuse in `UITableView`/`UICollectionView` safe:
    /// every `setImage` call cancels whatever load is already in flight on this image view
    /// before starting its own, so a cell that gets recycled mid-load never has a stale image
    /// land on it afterwards.
    private var loadTask: Task<Void, Never>? {
        get { objc_getAssociatedObject(base, &rdlLoadTaskKey) as? Task<Void, Never> }
        nonmutating set { objc_setAssociatedObject(base, &rdlLoadTaskKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }

    ///
    /// Cancels the in-flight load, if any, started by `setImage` on this image view.
    ///
    public func cancel() {
        loadTask?.cancel()
        loadTask = nil
    }

    ///
    /// Loads the image at `url` and sets it on this image view once it arrives.
    ///
    /// Cancels any load already in flight on this image view before starting — safe to call
    /// from `tableView(_:cellForRowAt:)`/`collectionView(_:cellForItemAt:)` even when cells are
    /// reused faster than their previous image finishes loading.
    ///
    /// - Parameters:
    ///    - url: The URL of the image.
    ///    - placeholder: The image to set immediately, shown until the load finishes.
    ///    - loader: The ``RDLImageLoader`` performing the request. Defaults to ``RDLImageLoader/shared``.
    ///    - completion: Called once the load finishes, on the main actor. Not called if the load
    ///    is cancelled by a later `setImage`/`cancel()` call on this image view.
    ///
    public func setImage(
        with url: URL,
        placeholder: UIImage? = nil,
        loader: RDLImageLoader = .shared,
        completion: (@Sendable (Result<UIImage, Error>) -> Void)? = nil
    ) {
        cancel()

        if let placeholder {
            base.image = placeholder
        }

        run({ try await loader.load(url: url) }, completion: completion)
    }

    ///
    /// Loads `task` and sets its image on this image view once it arrives.
    ///
    /// Use this when the request needs more than a URL — custom headers, authentication, a
    /// specific ``Property/cachePolicy(_:)``, and so on — by building `task` the same way a
    /// ``DataTask`` is built. Any ``RequestTask`` producing a ``TaskResult`` of `Data` works, so a
    /// ``MockedTask`` also drops in directly.
    ///
    /// Cancels any load already in flight on this image view before starting — safe to call
    /// from `tableView(_:cellForRowAt:)`/`collectionView(_:cellForItemAt:)` even when cells are
    /// reused faster than their previous image finishes loading.
    ///
    /// - Parameters:
    ///    - id: A stable identifier for the request, used to deduplicate concurrent loads. It
    ///    can't be derived automatically from an arbitrary ``RequestTask``, so callers supply it
    ///    explicitly — typically the URL or endpoint the request resolves to.
    ///    - task: The task that performs the request, e.g. a ``DataTask``.
    ///    - placeholder: The image to set immediately, shown until the load finishes.
    ///    - loader: The ``RDLImageLoader`` performing the request. Defaults to ``RDLImageLoader/shared``.
    ///    - completion: Called once the load finishes, on the main actor. Not called if the load
    ///    is cancelled by a later `setImage`/`cancel()` call on this image view.
    ///
    public func setImage<ImageTask: RequestTask<TaskResult<Data>>>(
        id: String,
        task: ImageTask,
        placeholder: UIImage? = nil,
        loader: RDLImageLoader = .shared,
        completion: (@Sendable (Result<UIImage, Error>) -> Void)? = nil
    ) {
        cancel()

        if let placeholder {
            base.image = placeholder
        }

        run({ try await loader.load(id: id, task: task) }, completion: completion)
    }

    // MARK: - Private methods

    private func run(
        _ load: @escaping @Sendable () async throws -> UIImage,
        completion: (@Sendable (Result<UIImage, Error>) -> Void)?
    ) {
        let imageView = base

        loadTask = Task { @MainActor in
            do {
                let image = try await load()
                try Task.checkCancellation()

                imageView.image = image
                completion?(.success(image))
            } catch is CancellationError {
                // A later `setImage`/`cancel()` call already replaced this load.
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                completion?(.failure(error))
            }
        }
    }
}

#endif
