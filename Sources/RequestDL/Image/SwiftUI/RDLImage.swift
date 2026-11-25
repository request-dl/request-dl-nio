//
// See LICENSE for this package's licensing information.
//

#if canImport(SwiftUI) && (canImport(UIKit) || canImport(AppKit))
import SwiftUI

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.URL
import struct Foundation.Data
#endif

/// A view that asynchronously loads and displays an image, using RequestDL's request pipeline
/// and cache.
///
/// `RDLImage` mirrors `AsyncImage`, with the same phase-driven and content/placeholder-driven
/// initializers built on a `URL`:
///
/// ```swift
/// RDLImage(url: url) { image in
///     image.resizable()
/// } placeholder: {
///     ProgressView()
/// }
///
/// RDLImage(url: url) { phase in
///     switch phase {
///     case .empty:
///         ProgressView()
///     case .success(let image):
///         image.resizable()
///     case .failure:
///         Image(systemName: "photo")
///     }
/// }
/// ```
///
/// Use the ``init(id:scale:transaction:loader:task:content:)`` initializer when the request needs
/// more than a URL (custom headers, authentication, a specific ``Property/cachePolicy(_:)``,
/// and so on) by building it the same way a ``DataTask`` is built:
///
/// ```swift
/// RDLImage(
///     id: "avatar",
///     task: DataTask {
///         BaseURL("cdn.example.com")
///         Path("avatar.png")
///         CustomHeader(name: "Authorization", value: token)
///     }
/// ) { phase in
///     ...
/// }
/// ```
///
/// Any ``RequestTask`` producing a ``TaskResult`` of `Data` works, so a ``MockedTask`` also drops
/// in directly, which is handy for previews and tests that shouldn't hit the network.
///
/// An image the `loader` already has in memory and that has not expired (see
/// ``RDLImageLoader/memoryCacheTimeToLive``) is the first phase of the view, in the same frame it
/// is created, instead of ``RDLImagePhase/empty``. What happens next depends on how the image is
/// asked for: with a `url` that is the whole answer and no request is made, and with a `task` the
/// request still runs and its result replaces the copy (the caller controls the cache policy,
/// headers and credentials, and the key is their own `id`). If that request fails, the copy stays
/// on screen.
///
/// Pass `refreshing: true` with a `url` to make the request anyway, as `task` does: the copy is
/// still the first phase, the request's result replaces it, and a failed request leaves it on
/// screen. ``RDLImageLoader/removeCachedImage(url:)`` forgets the copy for every view instead, and
/// the view then starts empty.
///
/// - Important: `id` identifies the request for both restarting the load (when it changes, the
/// current load is cancelled and a new one begins, same as `AsyncImage` reacting to a new `url`)
/// and deduplicating concurrent loads in ``RDLImageLoader``. It can't be derived automatically
/// from an arbitrary ``RequestTask``, so callers supply it explicitly, typically the URL or
/// endpoint the request resolves to.
public struct RDLImage<Content: View>: View {

    // MARK: - Private properties

    @State private var phase: RDLImagePhase

    private let id: String?
    private let key: CacheKey?
    private let loader: RDLImageLoader
    private let scale: CGFloat
    private let refreshing: Bool
    private let transaction: Transaction
    private let load: (@Sendable () async throws -> PlatformImage)?
    private let content: (RDLImagePhase) -> Content

    // MARK: - Public properties

    public var body: some View {
        content(phase)
            .task(id: id) {
                await runLoad()
            }
    }

    // MARK: - Private types

    /// What a copy in memory is looked up by, and what that copy means for the request.
    enum CacheKey: Equatable {
        /// A URL: a valid copy is the answer, and there is no request.
        case url(URL)

        /// A task's `id`: a valid copy is shown first, and the request still runs.
        case id(String)
    }

    /// What a view starts a load with, given what the loader has in memory.
    struct LoadPlan {

        /// The phase to show first: the copy in memory when there is one, empty otherwise.
        let phase: RDLImagePhase

        /// Whether `phase` is a copy in memory, which a failed request must not replace.
        let isCached: Bool

        /// Whether the request is made. `false` only for a URL with a valid copy.
        let runsRequest: Bool
    }

    /// The plan for `key`, looked up in `loader` at this moment, synchronously.
    ///
    /// `refreshing` only changes a URL with a valid copy: its request runs, as a task's does.
    static func plan(
        for key: CacheKey?,
        loader: RDLImageLoader,
        scale: CGFloat,
        refreshing: Bool = false
    ) -> LoadPlan {
        let cached: PlatformImage?
        let hasAnswer: Bool

        switch key {
        case .url(let url):
            cached = loader.cachedImage(url: url)
            hasAnswer = true

        case .id(let id):
            cached = loader.cachedImage(id: id)
            hasAnswer = false

        case nil:
            return LoadPlan(phase: .empty, isCached: false, runsRequest: false)
        }

        guard let cached else {
            return LoadPlan(phase: .empty, isCached: false, runsRequest: true)
        }

        return LoadPlan(
            phase: .success(Image(platformImage: cached, scale: scale)),
            isCached: true,
            runsRequest: !hasAnswer || refreshing
        )
    }

    // MARK: - Inits

    ///
    /// Creates an image that loads `url` and renders through `content`, driven by the current
    /// ``RDLImagePhase``.
    ///
    /// - Parameters:
    ///    - url: The URL of the image to load. Passing `nil` keeps the view in the ``RDLImagePhase/empty``
    ///    phase without starting a request.
    ///    - scale: The scale to interpret the loaded image at. Only meaningful on platforms
    ///    backed by `UIImage`; ignored on macOS.
    ///    - transaction: The transaction used when the phase changes.
    ///    - loader: The ``RDLImageLoader`` performing the request. Defaults to ``RDLImageLoader/shared``.
    ///    - refreshing: Pass `true` to make the request even when the image is in memory. The copy
    ///    is still the first phase, the request's result replaces it, and a failed request leaves
    ///    it. Defaults to `false`: a copy in memory is the answer and there is no request.
    ///    - content: A closure producing the view to render for the current phase.
    ///
    public init(
        url: URL?,
        scale: CGFloat = 1,
        transaction: Transaction = Transaction(),
        loader: RDLImageLoader = .shared,
        refreshing: Bool = false,
        @ViewBuilder content: @escaping (RDLImagePhase) -> Content
    ) {
        let key = url.map(CacheKey.url)

        self.id = url?.absoluteString
        self.key = key
        self.loader = loader
        self.scale = scale
        self.refreshing = refreshing
        self.transaction = transaction
        self.content = content
        self._phase = State(
            initialValue: Self.plan(for: key, loader: loader, scale: scale, refreshing: refreshing).phase
        )

        if let url {
            self.load = { try await loader.load(url: url) }
        } else {
            self.load = nil
        }
    }

    ///
    /// Creates an image that loads `task` and renders through `content`, driven by the current
    /// ``RDLImagePhase``.
    ///
    /// - Parameters:
    ///    - id: A stable identifier for the request. See the type-level discussion above.
    ///    - scale: The scale to interpret the loaded image at. Only meaningful on platforms
    ///    backed by `UIImage`; ignored on macOS.
    ///    - transaction: The transaction used when the phase changes.
    ///    - loader: The ``RDLImageLoader`` performing the request. Defaults to ``RDLImageLoader/shared``.
    ///    - task: The task that performs the request, e.g. a ``DataTask``.
    ///    - content: A closure producing the view to render for the current phase.
    ///
    public init<ImageTask: RequestTask<TaskResult<Data>>>(
        id: String,
        scale: CGFloat = 1,
        transaction: Transaction = Transaction(),
        loader: RDLImageLoader = .shared,
        task: ImageTask,
        @ViewBuilder content: @escaping (RDLImagePhase) -> Content
    ) {
        let key = CacheKey.id(id)

        self.id = id
        self.key = key
        self.loader = loader
        self.scale = scale
        self.refreshing = false
        self.transaction = transaction
        self.content = content
        self._phase = State(initialValue: Self.plan(for: key, loader: loader, scale: scale).phase)
        self.load = { try await loader.load(id: id, task: task) }
    }

    // MARK: - Private methods

    private func runLoad() async {
        guard let load else {
            phase = .empty
            return
        }

        // The view that was just created already shows the copy in memory, and this does not take
        // it away: it is looked up again, and what was there is only cleared when there is none.
        let plan = Self.plan(for: key, loader: loader, scale: scale, refreshing: refreshing)

        withTransaction(transaction) {
            phase = plan.phase
        }

        guard plan.runsRequest else {
            return
        }

        do {
            let image = try await load()
            try Task.checkCancellation()

            withTransaction(transaction) {
                phase = .success(Image(platformImage: image, scale: scale))
            }
        } catch is CancellationError {
            // The view's identity changed, or it disappeared, before the load finished. Leaving
            // `phase` untouched matches SwiftUI's own `.task(id:)` semantics: a cancelled task
            // shouldn't commit a result.
        } catch {
            guard !Task.isCancelled else {
                return
            }

            // A copy in memory that is on screen stays when its request fails.
            guard !plan.isCached else {
                return
            }

            withTransaction(transaction) {
                phase = .failure(error)
            }
        }
    }
}

// MARK: - Content/placeholder convenience inits

extension RDLImage {

    ///
    /// Creates an image that loads `url`, rendering `content` on success and `placeholder`
    /// otherwise.
    ///
    /// - Parameters:
    ///    - url: The URL of the image to load. Passing `nil` keeps `placeholder` on screen
    ///    without starting a request.
    ///    - scale: The scale to interpret the loaded image at. Only meaningful on platforms
    ///    backed by `UIImage`; ignored on macOS.
    ///    - loader: The ``RDLImageLoader`` performing the request. Defaults to ``RDLImageLoader/shared``.
    ///    - refreshing: Pass `true` to make the request even when the image is in memory. See
    ///    ``init(url:scale:transaction:loader:refreshing:content:)``.
    ///    - content: A closure producing the view to render once the image has loaded.
    ///    - placeholder: A closure producing the view to render while loading or on failure.
    ///
    public init<I: View, P: View>(
        url: URL?,
        scale: CGFloat = 1,
        loader: RDLImageLoader = .shared,
        refreshing: Bool = false,
        @ViewBuilder content: @escaping (Image) -> I,
        @ViewBuilder placeholder: @escaping () -> P
    ) where Content == _ConditionalContent<I, P> {
        self.init(url: url, scale: scale, loader: loader, refreshing: refreshing) { phase in
            if let image = phase.image {
                content(image)
            } else {
                placeholder()
            }
        }
    }
}

#endif
