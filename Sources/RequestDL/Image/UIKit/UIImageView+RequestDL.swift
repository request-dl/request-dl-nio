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

/// `@MainActor`-isolated because `UIImageView.image` is: setting it synchronously from
/// `setImage` (the `placeholder` assignment or clearing, ahead of the actual load) needs the compiler to
/// know it's already on the main actor, not just that it happens to run there in practice.
@MainActor
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
    /// The current image is replaced with `placeholder` right away, or cleared when it is
    /// `nil`, unless `keepsCurrentImageWhileLoading` is `true`.
    ///
    /// When `loader` already has this URL's image in memory and it has not expired (see
    /// ``RDLImageLoader/cachedImage(url:)`` and ``RDLImageLoader/memoryCacheTimeToLive``), that
    /// image is set in the same turn and **no request is made**: no disk read, no decode, no
    /// network. `completion` is called at once, with that image, before this method returns. Pass
    /// `refreshing: true` to make the request anyway: the image in memory is still shown first,
    /// and the load replaces it when it finishes.
    ///
    /// Cancels any load already in flight on this image view before starting, so it is safe to
    /// call from `tableView(_:cellForRowAt:)`/`collectionView(_:cellForItemAt:)` even when cells
    /// are reused faster than their previous image finishes loading.
    ///
    /// - Parameters:
    ///    - url: The URL of the image.
    ///    - placeholder: The image to set immediately, shown until the load finishes. Passing
    ///    `nil` (the default) clears the image view instead, so a reused view never keeps
    ///    showing the image of its previous owner while the new one loads. Ignored when
    ///    `keepsCurrentImageWhileLoading` is `true` and the view is already showing an image; a
    ///    view with none still gets it.
    ///    - loader: The ``RDLImageLoader`` performing the request. Defaults to ``RDLImageLoader/shared``.
    ///    - keepsCurrentImageWhileLoading: Pass `true` to leave whatever the image view is
    ///    showing untouched until the new image arrives, instead of replacing it with
    ///    `placeholder` (or clearing it). Defaults to `false`. Only useful when the same view reloads the *same*
    ///    content, e.g. refreshing an avatar, since otherwise the old image is wrong for a moment.
    ///    - refreshing: Pass `true` to make the request even when the image is in memory. Use it
    ///    for an explicit refresh (pull to refresh, say); ``RDLImageLoader/removeCachedImage(url:)``
    ///    forgets the image for every view instead. Defaults to `false`.
    ///    - completion: Called once the load finishes, on the main actor, or at once when the image
    ///    was in memory and there is no load. Not called if the load
    ///    is cancelled by a later `setImage`/`cancel()` call on this image view.
    ///
    public func setImage(
        with url: URL,
        placeholder: UIImage? = nil,
        loader: RDLImageLoader = .shared,
        keepsCurrentImageWhileLoading: Bool = false,
        refreshing: Bool = false,
        completion: (@Sendable (Result<UIImage, Error>) -> Void)? = nil
    ) {
        cancel()

        // An image this loader already loaded is shown at once, in place of the placeholder or of
        // an empty view, and for a URL that is the whole answer: there is no request. Asking to
        // refresh keeps the image on screen and makes the request anyway.
        if let cached = loader.cachedImage(url: url) {
            base.image = cached

            if !refreshing {
                completion?(.success(cached))
                return
            }
        } else if !keepsCurrentImageWhileLoading || base.image == nil {
            // Keeping the current image only means something when there is one: an empty view has
            // nothing to keep and shows the placeholder, which is what the parameter's name promises.
            base.image = placeholder
        }

        run({ try await loader.load(url: url) }, restoringOnFailure: nil, completion: completion)
    }

    ///
    /// Loads `task` and sets its image on this image view once it arrives.
    ///
    /// Use this when the request needs more than a URL (custom headers, authentication, a
    /// specific ``Property/cachePolicy(_:)``, and so on) by building `task` the same way a
    /// ``DataTask`` is built. Any ``RequestTask`` producing a ``TaskResult`` of `Data` works, so a
    /// ``MockedTask`` also drops in directly.
    ///
    /// The current image is replaced with `placeholder` right away, or cleared when it is
    /// `nil`, unless `keepsCurrentImageWhileLoading` is `true`. When `loader` already has this
    /// image in memory (see ``RDLImageLoader/cachedImage(id:)``), that image is set instead, in
    /// the same turn, and neither the placeholder nor an empty view is shown; the load still runs
    /// and sets its own result when it finishes.
    ///
    /// Unlike ``setImage(with:placeholder:loader:keepsCurrentImageWhileLoading:refreshing:completion:)``,
    /// the request is always made: the caller controls its cache policy, headers and credentials,
    /// and the key is the `id` they chose, so a copy in memory made for another account or another
    /// policy must never be the final answer: when the request fails, the view goes back to what it
    /// would have shown without the copy (`placeholder`, or what it was showing when
    /// `keepsCurrentImageWhileLoading` is `true`). Only an image loaded by URL is the answer for a
    /// URL, so one loaded here with an `id` equal to a URL's `absoluteString` is not what
    /// ``setImage(with:placeholder:loader:keepsCurrentImageWhileLoading:refreshing:completion:)``
    /// shows for it. When the account changes, call ``RDLImageLoader/removeAllCachedImages()``.
    ///
    /// Cancels any load already in flight on this image view before starting, so it is safe to
    /// call from `tableView(_:cellForRowAt:)`/`collectionView(_:cellForItemAt:)` even when cells
    /// are reused faster than their previous image finishes loading.
    ///
    /// - Parameters:
    ///    - id: A stable identifier for the request, used to deduplicate concurrent loads. It
    ///    can't be derived automatically from an arbitrary ``RequestTask``, so callers supply it
    ///    explicitly. Use a name that tells the request apart, such as the endpoint plus whatever
    ///    changes the answer (the user, the size); it does not have to be a URL.
    ///    - task: The task that performs the request, e.g. a ``DataTask``.
    ///    - placeholder: The image to set immediately, shown until the load finishes. Passing
    ///    `nil` (the default) clears the image view instead, so a reused view never keeps
    ///    showing the image of its previous owner while the new one loads. Ignored when
    ///    `keepsCurrentImageWhileLoading` is `true` and the view is already showing an image; a
    ///    view with none still gets it.
    ///    - loader: The ``RDLImageLoader`` performing the request. Defaults to ``RDLImageLoader/shared``.
    ///    - keepsCurrentImageWhileLoading: Pass `true` to leave whatever the image view is
    ///    showing untouched until the new image arrives, instead of replacing it with
    ///    `placeholder` (or clearing it). Defaults to `false`. Only useful when the same view reloads the *same*
    ///    content, e.g. refreshing an avatar, since otherwise the old image is wrong for a moment.
    ///    - completion: Called once the load finishes, on the main actor. Not called if the load
    ///    is cancelled by a later `setImage`/`cancel()` call on this image view.
    ///
    public func setImage<ImageTask: RequestTask<TaskResult<Data>>>(
        id: String,
        task: ImageTask,
        placeholder: UIImage? = nil,
        loader: RDLImageLoader = .shared,
        keepsCurrentImageWhileLoading: Bool = false,
        completion: (@Sendable (Result<UIImage, Error>) -> Void)? = nil
    ) {
        cancel()

        // What the view shows while the load runs when the loader has nothing for `id`. Keeping the
        // current image only means something when there is one: an empty view has nothing to keep
        // and shows the placeholder, which is what the parameter's name promises.
        let before = base.image
        let fallback = !keepsCurrentImageWhileLoading || before == nil ? placeholder : before

        // An image this loader already loaded is shown at once, in place of the placeholder or of
        // an empty view: the load below still runs and replaces it, but the view never goes
        // blank for the frames in between. It was not made by this request, so when the request
        // fails the view goes back to what it would show without it.
        let imageView = base
        let restore: (@MainActor () -> Void)?

        if let cached = loader.cachedImage(id: id) {
            imageView.image = cached
            restore = { imageView.image = fallback }
        } else {
            imageView.image = fallback
            restore = nil
        }

        run({ try await loader.load(id: id, task: task) }, restoringOnFailure: restore, completion: completion)
    }

    // MARK: - Private methods

    /// - Parameter restoringOnFailure: Called when the load fails, before `completion`, to take an
    /// image from memory off the view that the load was meant to confirm. `nil` leaves the view as
    /// it is.
    private func run(
        _ load: @escaping @Sendable () async throws -> UIImage,
        restoringOnFailure restore: (@MainActor () -> Void)?,
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

                restore?()
                completion?(.failure(error))
            }
        }
    }
}

#endif
