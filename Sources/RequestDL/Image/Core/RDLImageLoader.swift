//
// See LICENSE for this package's licensing information.
//

#if canImport(UIKit) || canImport(AppKit)

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.URL
import struct Foundation.Data
#endif

/// Loads and decodes images through RequestDL's request pipeline, reusing its cache
/// (``DataCache``, ``Property/cachePolicy(_:)``, ``Property/cacheStrategy(_:)``) and adding a
/// dedupe layer of its own.
///
/// Concurrent calls for the same `id` share a single in-flight download: the first call starts
/// it, and every other call that arrives before it finishes awaits the same result instead of
/// starting a second request. This is separate from, and on top of, RequestDL's own response
/// cache, which is what makes a *later*, non-concurrent request for the same image cheap.
///
/// The shared download is cancelled once every call waiting for it has been cancelled. While at
/// least one is still waiting it keeps running, so cancelling one call never takes the image
/// away from another.
public actor RDLImageLoader {

    /// The shared loader instance, used by RequestDL's SwiftUI, UIKit, AppKit and WatchKit
    /// integrations by default.
    public static let shared = RDLImageLoader()

    // MARK: - Public properties

    /// The cache ``load(url:)`` stores downloaded image data in. Defaults to a dedicated
    /// on-disk cache, separate from ``DataCache/shared``. Configure it directly (its capacities
    /// or, on Apple platforms, its `fileProtection`), or pass your own instance at init to
    /// share a cache across loaders.
    public let dataCache: DataCache

    // MARK: - Private properties

    /// In-flight downloads, keyed by the caller-supplied `id`.
    ///
    /// Cleared as soon as the task finishes (success or failure): this tracks concurrency, not
    /// results. A request that lands after this is cleared starts fresh, and RequestDL's own
    /// cache is what makes that repeat request cheap.
    private var tasks: [String: InFlight] = [:]

    private var nextGeneration = 0

    /// A download in flight and how many calls are waiting for it.
    ///
    /// `generation` tells one download for an `id` from the next one, so a late cancellation of
    /// a call that waited for an earlier download never touches a newer one.
    private struct InFlight {
        let task: Task<SendableImage, Error>
        let generation: Int
        var waiters: Int
    }

    // MARK: - Inits

    /// Creates a new, independent loader with its own dedupe bookkeeping and its own default
    /// on-disk cache. See ``dataCache``.
    ///
    /// Most callers should use ``shared`` instead, so unrelated call sites requesting the same
    /// image still dedupe against each other.
    ///
    /// - Note: This is a separate overload from ``init(dataCache:)``, rather than a default
    /// argument, to keep the `init()` symbol binary compatible.
    public init() {
        self.init(
            dataCache: DataCache(
                // Sized for a meaningful number of typical thumbnail/avatar-sized images
                // without growing unbounded; use `init(dataCache:)` for a different capacity.
                diskCapacity: 50 * 1_024 * 1_024,
                // Kept separate from `DataCache.shared`'s directory, so image bytes don't compete
                // for space with (or get evicted by) the unrelated HTTP responses the host app
                // caches by default.
                suiteName: "com.request-dl-nio.RDLImage"
            )
        )
    }

    /// Creates a new, independent loader with its own dedupe bookkeeping, backed by `dataCache`
    /// instead of the default one ``init()`` builds.
    ///
    /// - Parameter dataCache: The cache ``load(url:)`` uses. See ``dataCache``.
    public init(dataCache: DataCache) {
        self.dataCache = dataCache
    }

    // MARK: - Public methods

    ///
    /// Loads and decodes the image described by `task`.
    ///
    /// - Parameters:
    ///    - id: A stable identifier for the request, used to deduplicate concurrent loads that
    ///    describe the same image. Callers using ``load(url:)`` get this for free from the URL;
    ///    callers building their own ``RequestTask`` choose it themselves.
    ///    - task: The task that performs the request, e.g. a ``DataTask``.
    /// - Returns: The decoded image.
    /// - Throws: An error if the request fails or the response could not be decoded.
    ///
    public func load<Content: RequestTask<TaskResult<Data>>>(
        id: String,
        task: Content
    ) async throws -> PlatformImage {
        if var existing = tasks[id] {
            existing.waiters += 1
            tasks[id] = existing

            return try await waitFor(existing.task, id: id, generation: existing.generation)
        }

        // `.detached` rather than a plain `Task { ... }`: a plain `Task` would inherit this actor's
        // executor and run the CPU-bound `PlatformImage(data:)` decode on it. The decode touches no
        // actor state, and running it there would serialize every decode behind one another and
        // block unrelated `load()` calls from reaching their `tasks[id]` lookup.
        let newTask = Task.detached {
            let result = try await task.result()

            guard let image = PlatformImage(data: result.payload) else {
                throw RDLImageDecodingError()
            }

            return SendableImage(image)
        }

        let generation = nextGeneration
        nextGeneration += 1

        tasks[id] = InFlight(task: newTask, generation: generation, waiters: 1)

        return try await waitFor(newTask, id: id, generation: generation)
    }

    ///
    /// Loads and decodes the image at `url`, deduplicating against any other concurrent load of
    /// the same URL.
    ///
    /// Cached to disk by default, through ``dataCache``.
    ///
    /// - Parameter url: The URL of the image.
    /// - Returns: The decoded image.
    /// - Throws: An error if the request fails or the response could not be decoded.
    ///
    public func load(url: URL) async throws -> PlatformImage {
        let dataCache = self.dataCache

        return try await load(
            id: url.absoluteString,
            task: DataTask {
                URLImageProperty(url: url)
                    .cachePolicy(.disk)
                    .cache(url: dataCache.directoryURL)
            }
        )
    }

    ///
    /// Loads and decodes the image described by `content`, in the same manner as ``DataTask``.
    ///
    /// Use this when the request needs more than a URL (custom headers, authentication, a
    /// specific ``Property/cachePolicy(_:)``, and so on).
    ///
    /// - Parameters:
    ///    - id: A stable identifier for the request, used to deduplicate concurrent loads that
    ///    describe the same image.
    ///    - content: The content describing the request.
    /// - Returns: The decoded image.
    /// - Throws: An error if the request fails or the response could not be decoded.
    ///
    public func load<Content: Property>(
        id: String,
        @PropertyBuilder content: () -> Content
    ) async throws -> PlatformImage {
        try await load(id: id, task: DataTask(content: content))
    }

    // MARK: - Private methods

    /// Waits for `task`, which the caller already counted as one of its waiters.
    ///
    /// A plain `await task.value` would ignore this caller's cancellation, since the download
    /// runs in a detached task of its own. The cancellation handler gives the caller's place
    /// back instead, and the last one to leave cancels the download.
    private func waitFor(
        _ task: Task<SendableImage, Error>,
        id: String,
        generation: Int
    ) async throws -> PlatformImage {
        defer { finish(id: id, generation: generation) }

        return try await withTaskCancellationHandler {
            try await task.value.image
        } onCancel: {
            Task { await self.leave(id: id, generation: generation) }
        }
    }

    /// Gives up one waiter's place, cancelling the download when it was the last.
    private func leave(id: String, generation: Int) {
        guard var inFlight = tasks[id], inFlight.generation == generation else {
            return
        }

        inFlight.waiters -= 1

        guard inFlight.waiters <= 0 else {
            tasks[id] = inFlight
            return
        }

        inFlight.task.cancel()
        tasks[id] = nil
    }

    /// Forgets the download once a call has its outcome, unless a newer one took its place.
    private func finish(id: String, generation: Int) {
        if tasks[id]?.generation == generation {
            tasks[id] = nil
        }
    }
}

#endif
