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
/// A call that is cancelled stops waiting at once, with a `CancellationError`, whether it was
/// alone or one of several. The shared download is cancelled once every call waiting for it has
/// been cancelled. While at least one is still waiting it keeps running, so cancelling one call
/// never takes the image away from another.
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

    private var nextWaiter = 0

    /// A download in flight and the calls waiting for it, each with its own continuation.
    ///
    /// A call has its own continuation, rather than awaiting the download's task, so that it can
    /// stop waiting on its own: awaiting a `Task` is not interrupted by the cancellation of the
    /// caller, and the download has to go on for the others.
    ///
    /// `generation` tells one download for an `id` from the next one, so a late cancellation of
    /// a call that waited for an earlier download never touches a newer one.
    private struct InFlight {
        let task: Task<Void, Never>
        let generation: Int
        var waiters: [Int: CheckedContinuation<SendableImage, Error>]
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
        if let existing = tasks[id] {
            return try await waitFor(id: id, generation: existing.generation).image
        }

        let generation = nextGeneration
        nextGeneration += 1

        // `.detached` rather than a plain `Task { ... }`: a plain `Task` would inherit this actor's
        // executor and run the CPU-bound `PlatformImage(data:)` decode on it. The decode touches no
        // actor state, and running it there would serialize every decode behind one another and
        // block unrelated `load()` calls from reaching their `tasks[id]` lookup.
        let newTask = Task.detached {
            let result: Result<SendableImage, Error>

            do {
                let response = try await task.result()

                guard let image = PlatformImage(data: response.payload) else {
                    throw RDLImageDecodingError()
                }

                result = .success(SendableImage(image))
            } catch {
                result = .failure(error)
            }

            await self.complete(id: id, generation: generation, with: result)
        }

        tasks[id] = InFlight(task: newTask, generation: generation, waiters: [:])

        return try await waitFor(id: id, generation: generation).image
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

    /// Waits for the download of `id`, as one of the calls it is shared by.
    ///
    /// The call's place is taken in the same turn of the actor that found or made the download,
    /// so the download cannot finish before there is a continuation to hand its result to. When
    /// the call is cancelled it leaves at once: its continuation is resumed with a
    /// `CancellationError` and the download goes on for the others, or is cancelled if it was
    /// the last.
    private func waitFor(id: String, generation: Int) async throws -> SendableImage {
        let waiter = nextWaiter
        nextWaiter += 1

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard var inFlight = tasks[id], inFlight.generation == generation else {
                    continuation.resume(throwing: CancellationError())
                    return
                }

                inFlight.waiters[waiter] = continuation
                tasks[id] = inFlight
            }
        } onCancel: {
            Task { await self.leave(id: id, generation: generation, waiter: waiter) }
        }
    }

    /// Gives up one call's place, resuming it with a `CancellationError`, and cancels the
    /// download when it was the last.
    private func leave(id: String, generation: Int, waiter: Int) {
        guard
            var inFlight = tasks[id],
            inFlight.generation == generation,
            let continuation = inFlight.waiters.removeValue(forKey: waiter)
        else {
            return
        }

        continuation.resume(throwing: CancellationError())

        guard inFlight.waiters.isEmpty else {
            tasks[id] = inFlight
            return
        }

        inFlight.task.cancel()
        tasks[id] = nil
    }

    /// Hands the outcome of the download to every call still waiting for it, and forgets it.
    /// Nothing is left to do when the download was cancelled with its last call.
    private func complete(id: String, generation: Int, with result: Result<SendableImage, Error>) {
        guard let inFlight = tasks[id], inFlight.generation == generation else {
            return
        }

        tasks[id] = nil

        for continuation in inFlight.waiters.values {
            continuation.resume(with: result)
        }
    }

    /// How many calls are waiting for the download of `id`.
    func waiterCountForTesting(id: String) -> Int {
        tasks[id]?.waiters.count ?? 0
    }
}

#endif
