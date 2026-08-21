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
/// starting a second request. This is separate from — and on top of — RequestDL's own response
/// cache, which is what makes a *later*, non-concurrent request for the same image cheap.
public actor RDLImageLoader {

    /// The shared loader instance, used by RequestDL's SwiftUI, UIKit, AppKit and WatchKit
    /// integrations by default.
    public static let shared = RDLImageLoader()

    // MARK: - Private properties

    /// In-flight downloads, keyed by the caller-supplied `id`.
    ///
    /// Cleared as soon as the task finishes (success or failure): this tracks concurrency, not
    /// results. A request that lands after this is cleared starts fresh rather than reusing a
    /// stale entry — RequestDL's own cache is what makes that repeat request cheap.
    private var tasks: [String: Task<SendableImage, Error>] = [:]

    // MARK: - Inits

    /// Creates a new, independent loader with its own dedupe bookkeeping.
    ///
    /// Most callers should use ``shared`` instead, so unrelated call sites requesting the same
    /// image still dedupe against each other.
    public init() {}

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
            return try await existing.value.image
        }

        let newTask = Task<SendableImage, Error> {
            let result = try await task.result()

            guard let image = PlatformImage(data: result.payload) else {
                throw RDLImageDecodingError()
            }

            return SendableImage(image)
        }

        tasks[id] = newTask
        defer { tasks[id] = nil }

        return try await newTask.value.image
    }

    ///
    /// Loads and decodes the image at `url`, deduplicating against any other concurrent load of
    /// the same URL.
    ///
    /// - Parameter url: The URL of the image.
    /// - Returns: The decoded image.
    /// - Throws: An error if the request fails or the response could not be decoded.
    ///
    public func load(url: URL) async throws -> PlatformImage {
        try await load(
            id: url.absoluteString,
            task: DataTask { URLImageProperty(url: url) }
        )
    }

    ///
    /// Loads and decodes the image described by `content`, in the same manner as ``DataTask``.
    ///
    /// Use this when the request needs more than a URL — custom headers, authentication, a
    /// specific ``Property/cachePolicy(_:)``, and so on.
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
}

#endif
