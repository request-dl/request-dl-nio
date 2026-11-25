//
// See LICENSE for this package's licensing information.
//

#if canImport(WatchKit)
import WatchKit

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.URL
import struct Foundation.Data
#endif

/// Backs the in-flight load tracked on each `WKInterfaceImage`, via the standard Swift
/// associated-object pattern: only this variable's stable address is ever used, its value is
/// never read or written, so `nonisolated(unsafe)` is safe.
private nonisolated(unsafe) var rdlLoadTaskKey: UInt8 = 0

extension WKInterfaceImage: RDLCompatible {}

/// `@MainActor`-isolated because, unlike `UIImageView`/`NSImageView`, `WKInterfaceImage` isn't
/// annotated `@MainActor` in the WatchKit overlay. Capturing `base` into the `Task` below
/// would otherwise be flagged as sending a non-`Sendable`, non-isolated value across
/// isolation domains. It also matches how `WKInterfaceObject` is meant to be driven.
@MainActor
extension RDLWrapper where Base: WKInterfaceImage {

    /// The in-flight load started by `setImage`, if any.
    ///
    /// Reading and writing this is what makes reuse of rows in a `WKInterfaceTable` safe: every
    /// `setImage` call cancels whatever load is already in flight on this interface image before
    /// starting its own, so a row that gets recycled mid-load never has a stale image land on it
    /// afterwards.
    private var loadTask: Task<Void, Never>? {
        get { objc_getAssociatedObject(base, &rdlLoadTaskKey) as? Task<Void, Never> }
        nonmutating set { objc_setAssociatedObject(base, &rdlLoadTaskKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }

    ///
    /// Cancels the in-flight load, if any, started by `setImage` on this interface image.
    ///
    public func cancel() {
        loadTask?.cancel()
        loadTask = nil
    }

    ///
    /// Loads the image at `url` and sets it on this interface image once it arrives.
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
    /// Cancels any load already in flight on this interface image before starting, so it is safe
    /// to call from a `WKInterfaceTable` row controller even when rows are reused faster than
    /// their previous image finishes loading.
    ///
    /// - Parameters:
    ///    - url: The URL of the image.
    ///    - placeholder: The image to set immediately, shown until the load finishes. Passing
    ///    `nil` (the default) clears the interface image instead, so a reused view never keeps
    ///    showing the image of its previous owner while the new one loads. Ignored when
    ///    `keepsCurrentImageWhileLoading` is `true`: a `WKInterfaceImage` cannot be read, so
    ///    there is no telling whether it is empty.
    ///    - loader: The ``RDLImageLoader`` performing the request. Defaults to ``RDLImageLoader/shared``.
    ///    - keepsCurrentImageWhileLoading: Pass `true` to leave whatever the interface image is
    ///    showing untouched until the new image arrives, instead of replacing it with
    ///    `placeholder` (or clearing it). Defaults to `false`. Only useful when the same view reloads the *same*
    ///    content, e.g. refreshing an avatar, since otherwise the old image is wrong for a moment.
    ///    - refreshing: Pass `true` to make the request even when the image is in memory. Use it
    ///    for an explicit refresh (pull to refresh, say); ``RDLImageLoader/removeCachedImage(url:)``
    ///    forgets the image for every view instead. Defaults to `false`.
    ///    - completion: Called once the load finishes, on the main actor, or at once when the image
    ///    was in memory and there is no load. Not called if the load
    ///    is cancelled by a later `setImage`/`cancel()` call on this interface image.
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

        // An image this loader already loaded is shown at once, whatever `keepsCurrentImageWhileLoading`
        // is: that needs no reading of what the interface image shows, which is not possible. For a
        // URL that is the whole answer, with no request. Asking to refresh keeps the image on
        // screen and makes the request anyway.
        if let cached = loader.cachedImage(url: url) {
            base.setImage(cached)

            if !refreshing {
                completion?(.success(cached))
                return
            }
        } else if !keepsCurrentImageWhileLoading {
            base.setImage(placeholder)
        }

        run({ try await loader.load(url: url) }, completion: completion)
    }

    ///
    /// Loads `task` and sets its image on this interface image once it arrives.
    ///
    /// Use this when the request needs more than a URL (custom headers, authentication, a
    /// specific ``Property/cachePolicy(_:)``, and so on) by building `task` the same way a
    /// ``DataTask`` is built. Any ``RequestTask`` producing a ``TaskResult`` of `Data` works, so a
    /// ``MockedTask`` also drops in directly.
    ///
    /// The current image is replaced with `placeholder` right away, or cleared when it is
    /// `nil`, unless `keepsCurrentImageWhileLoading` is `true`. When `loader` already has this
    /// image in memory (see ``RDLImageLoader/cachedImage(id:)``), that image is set instead, in
    /// the same turn, whatever `keepsCurrentImageWhileLoading` is; the load still runs and sets its
    /// own result when it finishes.
    ///
    /// Unlike ``setImage(with:placeholder:loader:keepsCurrentImageWhileLoading:refreshing:completion:)``,
    /// the request is always made: the caller controls its cache policy, headers and credentials,
    /// and the key is the `id` they chose, so a copy in memory made for another account or another
    /// policy must never be the final answer.
    ///
    /// Cancels any load already in flight on this interface image before starting, so it is safe
    /// to call from a `WKInterfaceTable` row controller even when rows are reused faster than
    /// their previous image finishes loading.
    ///
    /// - Parameters:
    ///    - id: A stable identifier for the request, used to deduplicate concurrent loads. It
    ///    can't be derived automatically from an arbitrary ``RequestTask``, so callers supply it
    ///    explicitly, typically the URL or endpoint the request resolves to.
    ///    - task: The task that performs the request, e.g. a ``DataTask``.
    ///    - placeholder: The image to set immediately, shown until the load finishes. Passing
    ///    `nil` (the default) clears the interface image instead, so a reused view never keeps
    ///    showing the image of its previous owner while the new one loads. Ignored when
    ///    `keepsCurrentImageWhileLoading` is `true`: a `WKInterfaceImage` cannot be read, so
    ///    there is no telling whether it is empty.
    ///    - loader: The ``RDLImageLoader`` performing the request. Defaults to ``RDLImageLoader/shared``.
    ///    - keepsCurrentImageWhileLoading: Pass `true` to leave whatever the interface image is
    ///    showing untouched until the new image arrives, instead of replacing it with
    ///    `placeholder` (or clearing it). Defaults to `false`. Only useful when the same view reloads the *same*
    ///    content, e.g. refreshing an avatar, since otherwise the old image is wrong for a moment.
    ///    - completion: Called once the load finishes, on the main actor. Not called if the load
    ///    is cancelled by a later `setImage`/`cancel()` call on this interface image.
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

        // An image this loader already loaded is shown at once. This needs no reading of what the
        // interface image shows, which is not possible, so it works whatever `keepsCurrentImageWhileLoading` is.
        if let cached = loader.cachedImage(id: id) {
            base.setImage(cached)
        } else if !keepsCurrentImageWhileLoading {
            base.setImage(placeholder)
        }

        run({ try await loader.load(id: id, task: task) }, completion: completion)
    }

    // MARK: - Private methods

    private func run(
        _ load: @escaping @Sendable () async throws -> UIImage,
        completion: (@Sendable (Result<UIImage, Error>) -> Void)?
    ) {
        let interfaceImage = base

        loadTask = Task { @MainActor in
            do {
                let image = try await load()
                try Task.checkCancellation()

                interfaceImage.setImage(image)
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
