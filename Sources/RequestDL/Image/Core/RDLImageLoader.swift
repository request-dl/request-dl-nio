//
// See LICENSE for this package's licensing information.
//

#if canImport(UIKit) || canImport(AppKit)

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.URL
import struct Foundation.Data
import typealias Foundation.TimeInterval
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
/// Calls by URL (``load(url:)``) and calls by task (``load(id:task:)``) are told apart even when
/// the `id` of the second is the `absoluteString` of the first: a task carries headers,
/// credentials and a cache policy of its own, so a download made for it is never handed to a
/// call by URL, and the other way around. Two calls by URL for the same URL do share one, and so
/// do two calls by task for the same `id`. A call that starts after ``removeCachedImage(id:)`` (or
/// ``removeAllCachedImages()``) does not join a download that began before it either: that
/// download would hand it what the removal was meant to get rid of (the old avatar, after the
/// user changed it), so it starts its own. The earlier download is not cancelled, and still
/// returns to the calls that were waiting for it.
///
/// The images that were loaded are also kept decoded in memory, up to ``memoryCacheLimit``
/// bytes and for ``memoryCacheTimeToLive`` seconds each, so a view can show one at once: see
/// ``cachedImage(id:)``. What the copy in memory stands in for depends on how the image is asked
/// for:
///
/// - **By URL** (``load(url:)``'s callers, `setImage(with:)` and `RDLImage(url:)`): a valid copy
///   is the answer, and the request is not made at all, with no disk read or decode. The URL is
///   all that identifies the request, so there is nothing a copy could be wrong about but its age,
///   which the time to live bounds. Only a copy that ``load(url:)`` made counts: an image loaded
///   by ``load(id:task:)`` is not the answer for that URL, even when its `id` is the same string,
///   because the task may have sent credentials the URL path does not.
/// - **By task** (`setImage(id:task:)` and `RDLImage(id:task:)`): the copy is only shown first,
///   and the request still runs and replaces it. The caller owns the cache policy, headers and
///   credentials, and the key is the `id` they chose, so a copy made for another account or
///   another policy must never be the final word: when the request fails, the views go back to
///   what they showed before the copy.
///
/// ``load(url:)`` and ``load(id:task:)`` themselves never read the copy: they always run the
/// request, and what they load replaces it.
///
/// The key of a copy is only the `id` (or the URL), not who is signed in. When the account
/// changes, call ``removeAllCachedImages()``.
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

    /// How many bytes of decoded images are kept in memory, counted as their pixels at four
    /// bytes each. Defaults to 64 MB.
    ///
    /// The system also empties the cache when memory runs low, whatever this is. Changing it
    /// applies at once; `0` turns the cache off, drops what it holds, and keeps nothing from then
    /// on, which brings back showing a view empty until an image that was loaded before arrives
    /// again, and making the request for every URL.
    public nonisolated var memoryCacheLimit: Int {
        get { memoryCache.limit }
        set { memoryCache.limit = newValue }
    }

    /// How many seconds an image stays valid in memory, counted from when it was loaded (not
    /// from when it was last shown). Defaults to 300, 5 minutes. `nil`, or `.infinity`, keeps it
    /// until the limit or the system evicts it.
    ///
    /// Once it is over, the image is a miss and is removed: a view asked for it is cleared (or
    /// shows its placeholder) and the request runs. Applies to the images already in memory.
    ///
    /// It is what bounds how old an image shown without a request can be, so it is short: an
    /// image that changes behind the same URL is seen again within this time. `0` makes every
    /// image a miss. To force the request for one call, see `refreshing` in `setImage(with:)`, or
    /// call ``removeCachedImage(url:)`` first.
    public nonisolated var memoryCacheTimeToLive: TimeInterval? {
        get { memoryCache.timeToLive }
        set { memoryCache.timeToLive = newValue }
    }

    // MARK: - Private properties

    private let memoryCache: RDLImageMemoryCache

    /// In-flight downloads, by generation.
    ///
    /// Cleared as soon as the task finishes (success or failure): this tracks concurrency, not
    /// results. A request that lands after this is cleared starts fresh, and RequestDL's own
    /// cache is what makes that repeat request cheap.
    ///
    /// More than one can be there for the same `id` and origin: a download that began before an
    /// image was removed goes on for the calls that were waiting for it, while the calls that came
    /// after the removal wait for a new one.
    private var flights: [Int: InFlight] = [:]

    /// The download new calls join, for each origin and `id`: the latest one, unless an image was
    /// removed since it began.
    private var current: [FlightKey: Int] = [:]

    private var nextGeneration = 0

    private var nextWaiter = 0

    /// A download in flight and the calls waiting for it, each with its own continuation.
    ///
    /// A call has its own continuation, rather than awaiting the download's task, so that it can
    /// stop waiting on its own: awaiting a `Task` is not interrupted by the cancellation of the
    /// caller, and the download has to go on for the others.
    ///
    /// The generation, the key of ``flights``, tells one download for an `id` from the next one,
    /// so a late cancellation of a call that waited for an earlier download never touches a newer
    /// one.
    private struct InFlight {
        let task: Task<Void, Never>
        let key: FlightKey

        /// ``RDLImageMemoryCache/removals`` when the download began: if it is not the same when the
        /// download ends, an image was removed meanwhile and the result is not kept in memory.
        let removalsAtStart: Int
        var waiters: [Int: CheckedContinuation<SendableImage, Error>]
    }

    /// What a download is for: the calls that share one.
    private struct FlightKey: Hashable {
        let origin: Origin
        let id: String
    }

    /// Which kind of call made a download, and so what the image it produced may stand in for.
    enum Origin: Hashable, Sendable {

        /// ``load(url:)``: the request is the URL alone.
        case url

        /// ``load(id:task:)``: the request is the caller's, with whatever headers and credentials
        /// it carries.
        case task
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
        self.init(dataCache: dataCache, memoryCacheLimit: RDLImageMemoryCache.defaultLimit)
    }

    /// Creates a new, independent loader backed by `dataCache`, keeping at most
    /// `memoryCacheLimit` bytes of decoded images in memory.
    ///
    /// - Parameters:
    ///    - dataCache: The cache ``load(url:)`` uses. See ``dataCache``.
    ///    - memoryCacheLimit: See ``memoryCacheLimit``. `0` keeps no image in memory.
    ///    - memoryCacheTimeToLive: See ``memoryCacheTimeToLive``. Defaults to 5 minutes.
    public init(
        dataCache: DataCache,
        memoryCacheLimit: Int,
        memoryCacheTimeToLive: TimeInterval? = 300
    ) {
        self.dataCache = dataCache
        self.memoryCache = RDLImageMemoryCache(limit: memoryCacheLimit, timeToLive: memoryCacheTimeToLive)
    }

    // MARK: - Public methods

    ///
    /// The image a load for `id` last finished with, when it is still in memory and its time to
    /// live (``memoryCacheTimeToLive``) is not over.
    ///
    /// It answers at once and from any thread, which is what lets a view that is asked to show
    /// `id` again put the image on screen in the same turn, instead of clearing it until the load
    /// finishes. `id` is the one given to ``load(id:task:)``, and the URL's `absoluteString` for
    /// ``load(url:)``: that image is shown first by a view that loads by task, which then runs its
    /// own request, but it is not the answer for that request.
    ///
    /// An image is only kept when a load finishes with success. Whatever the request's cache
    /// policy says about the response does not apply to this copy, so it can be older than what
    /// the request would return now, by up to the time to live. It is what a view shows first, and
    /// for a URL it is also the answer, with no request: see the discussion of this type.
    ///
    /// - Parameter id: The identifier of the load.
    /// - Returns: The image, or `nil` when none was loaded, it was removed, it expired, or it was
    ///   evicted.
    ///
    public nonisolated func cachedImage(id: String) -> PlatformImage? {
        memoryCache.image(for: id)
    }

    ///
    /// The image ``load(url:)`` last finished with for `url`, when it is still in memory.
    ///
    /// See ``cachedImage(id:)``. An image that ``load(id:task:)`` loaded is not returned, even
    /// when its `id` is `url.absoluteString`: this is the answer for a request made with the URL
    /// alone, and that image came from a request that may have carried credentials.
    ///
    /// - Parameter url: The URL of the image.
    ///
    public nonisolated func cachedImage(url: URL) -> PlatformImage? {
        memoryCache.image(for: url.absoluteString, origin: .url)
    }

    ///
    /// Forgets the image in memory for `id`, so the next view asked to show it starts empty, or
    /// with its placeholder, until a load finishes. It does not touch ``dataCache``.
    ///
    /// A load that was already running when this is called does not put its result back in
    /// memory: it still returns the image to whoever waited for it, but a later look-up is a miss.
    ///
    /// - Parameter id: The identifier of the load.
    ///
    public nonisolated func removeCachedImage(id: String) {
        memoryCache.remove(id)
    }

    ///
    /// Forgets the image in memory for `url`. See ``removeCachedImage(id:)``.
    ///
    /// - Parameter url: The URL of the image.
    ///
    public nonisolated func removeCachedImage(url: URL) {
        memoryCache.remove(url.absoluteString)
    }

    ///
    /// Forgets every image in memory. It does not touch ``dataCache``.
    ///
    public nonisolated func removeAllCachedImages() {
        memoryCache.removeAll()
    }

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
        try await load(origin: .task, id: id, task: task)
    }

    /// Loads `task` for `origin`, sharing the download with the calls of the same origin and `id`
    /// that began since the last removal from memory.
    func load<Content: RequestTask<TaskResult<Data>>>(
        origin: Origin,
        id: String,
        task: Content
    ) async throws -> PlatformImage {
        let key = FlightKey(origin: origin, id: id)
        let removalsAtStart = memoryCache.removals

        // A download that began before an image was removed is not joined, and not cancelled: its
        // waiters are still waiting for it, and `current` moves on to the new one.
        if let generation = current[key], flights[generation]?.removalsAtStart == removalsAtStart {
            return try await waitFor(generation: generation).image
        }

        let generation = nextGeneration
        nextGeneration += 1

        // `.detached` rather than a plain `Task { ... }`: a plain `Task` would inherit this actor's
        // executor and run the CPU-bound `PlatformImage(data:)` decode on it. The decode touches no
        // actor state, and running it there would serialize every decode behind one another and
        // block unrelated `load()` calls from reaching their `current` lookup.
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

            await self.complete(generation: generation, with: result)
        }

        flights[generation] = InFlight(task: newTask, key: key, removalsAtStart: removalsAtStart, waiters: [:])
        current[key] = generation

        return try await waitFor(generation: generation).image
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
            origin: .url,
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

    /// Waits for the download of `generation`, as one of the calls it is shared by.
    ///
    /// The call's place is taken in the same turn of the actor that found or made the download,
    /// so the download cannot finish before there is a continuation to hand its result to. When
    /// the call is cancelled it leaves at once: its continuation is resumed with a
    /// `CancellationError` and the download goes on for the others, or is cancelled if it was
    /// the last.
    private func waitFor(generation: Int) async throws -> SendableImage {
        let waiter = nextWaiter
        nextWaiter += 1

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard var inFlight = flights[generation] else {
                    continuation.resume(throwing: CancellationError())
                    return
                }

                inFlight.waiters[waiter] = continuation
                flights[generation] = inFlight
            }
        } onCancel: {
            Task { await self.leave(generation: generation, waiter: waiter) }
        }
    }

    /// Gives up one call's place, resuming it with a `CancellationError`, and cancels the
    /// download when it was the last.
    private func leave(generation: Int, waiter: Int) {
        guard
            var inFlight = flights[generation],
            let continuation = inFlight.waiters.removeValue(forKey: waiter)
        else {
            return
        }

        continuation.resume(throwing: CancellationError())

        guard inFlight.waiters.isEmpty else {
            flights[generation] = inFlight
            return
        }

        inFlight.task.cancel()
        forget(generation: generation, key: inFlight.key)
    }

    /// Hands the outcome of the download to every call still waiting for it, and forgets it.
    /// Nothing is left to do when the download was cancelled with its last call.
    private func complete(generation: Int, with result: Result<SendableImage, Error>) {
        guard let inFlight = flights[generation] else {
            return
        }

        forget(generation: generation, key: inFlight.key)

        // Only an image that was loaded is kept: a failure leaves what is there as it was.
        if case .success(let image) = result {
            memoryCache.insert(
                image.image,
                for: inFlight.key.id,
                origin: inFlight.key.origin,
                ifRemovalsAre: inFlight.removalsAtStart
            )
        }

        for continuation in inFlight.waiters.values {
            continuation.resume(with: result)
        }
    }

    /// Drops `generation`, and stops new calls from joining it when it is the one they would.
    private func forget(generation: Int, key: FlightKey) {
        flights[generation] = nil

        if current[key] == generation {
            current[key] = nil
        }
    }

    /// How many calls are waiting for the downloads of `id`, of the given origin or of any.
    func waiterCountForTesting(id: String, origin: Origin? = nil) -> Int {
        flights.values
            .filter { $0.key.id == id && (origin == nil || $0.key.origin == origin) }
            .reduce(0) { $0 + $1.waiters.count }
    }
}

#endif
