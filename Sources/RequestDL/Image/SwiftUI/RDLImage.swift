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
/// more than a URL — custom headers, authentication, a specific ``Property/cachePolicy(_:)``, and
/// so on — by building it the same way a ``DataTask`` is built:
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
/// in directly — handy for previews and tests that shouldn't hit the network.
///
/// - Important: `id` identifies the request for both restarting the load (when it changes, the
/// current load is cancelled and a new one begins, same as `AsyncImage` reacting to a new `url`)
/// and deduplicating concurrent loads in ``RDLImageLoader``. It can't be derived automatically
/// from an arbitrary ``RequestTask``, so callers supply it explicitly — typically the URL or
/// endpoint the request resolves to.
public struct RDLImage<Content: View>: View {

    // MARK: - Private properties

    @State private var phase: RDLImagePhase = .empty

    private let id: String?
    private let scale: CGFloat
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
    ///    - content: A closure producing the view to render for the current phase.
    ///
    public init(
        url: URL?,
        scale: CGFloat = 1,
        transaction: Transaction = Transaction(),
        loader: RDLImageLoader = .shared,
        @ViewBuilder content: @escaping (RDLImagePhase) -> Content
    ) {
        self.id = url?.absoluteString
        self.scale = scale
        self.transaction = transaction
        self.content = content

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
        self.id = id
        self.scale = scale
        self.transaction = transaction
        self.content = content
        self.load = { try await loader.load(id: id, task: task) }
    }

    // MARK: - Private methods

    private func runLoad() async {
        guard let load else {
            phase = .empty
            return
        }

        withTransaction(transaction) {
            phase = .empty
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
    ///    - content: A closure producing the view to render once the image has loaded.
    ///    - placeholder: A closure producing the view to render while loading or on failure.
    ///
    public init<I: View, P: View>(
        url: URL?,
        scale: CGFloat = 1,
        loader: RDLImageLoader = .shared,
        @ViewBuilder content: @escaping (Image) -> I,
        @ViewBuilder placeholder: @escaping () -> P
    ) where Content == _ConditionalContent<I, P> {
        self.init(url: url, scale: scale, loader: loader) { phase in
            if let image = phase.image {
                content(image)
            } else {
                placeholder()
            }
        }
    }
}

#endif
