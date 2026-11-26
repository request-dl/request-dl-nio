//
// See LICENSE for this package's licensing information.
//

#if canImport(UIKit) || canImport(AppKit)

import Foundation

/// The decoded images an ``RDLImageLoader`` has loaded, kept in memory so a view can show one in
/// the same turn it is asked to, instead of after a read from the disk and a decode.
///
/// An `NSCache`: thread safe, so it is read from the main actor without waiting for the loader,
/// and emptied by the system when memory runs low. It is bounded by the cost of the images,
/// their size in memory in bytes, not by how many there are.
///
/// A limit of `0` turns it off: nothing is kept, and what was kept is dropped.
///
/// An entry also has a time to live, counted from the moment it was written (not from the last
/// time it was read): once it is over, the entry is a miss and is removed. `nil` keeps entries
/// until the limit or the system evicts them.
final class RDLImageMemoryCache: @unchecked Sendable {

    /// What a loader keeps when it is not told otherwise: room for a few dozen thumbnails or a few
    /// full-screen images.
    static let defaultLimit = 64 * 1_024 * 1_024

    /// What entries live for when a loader is not told otherwise: 5 minutes.
    static let defaultTimeToLive: TimeInterval = 300

    private final class Entry {
        let image: PlatformImage
        let storedAt: Date

        init(_ image: PlatformImage, storedAt: Date) {
            self.image = image
            self.storedAt = storedAt
        }
    }

    private let cache = NSCache<NSString, Entry>()
    private let lock = NSLock()
    private var _limit = 0
    private var _timeToLive: TimeInterval?
    private var _removals = 0
    private let now: @Sendable () -> Date

    init(
        limit: Int,
        timeToLive: TimeInterval? = RDLImageMemoryCache.defaultTimeToLive,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.now = now
        self.limit = limit
        self.timeToLive = timeToLive
    }

    /// How long an entry is good for, in seconds, from when it was written. `nil` (or
    /// `.infinity`) for as long as it stays in memory. Applies to the entries already there.
    var timeToLive: TimeInterval? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _timeToLive
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _timeToLive = newValue
        }
    }

    /// How many times an image was removed, or the cache was emptied, since it was created.
    ///
    /// A load notes it before it starts and hands it back to ``insert(_:for:ifRemovalsAre:)``,
    /// which keeps the image only when it has not changed: a removal that happened while the load
    /// was running is not undone by the load finishing. It counts every removal, not just the
    /// one of the same `id`, so an unrelated removal can cost a running load its write; that is
    /// a miss later, never a stale image.
    var removals: Int {
        lock.lock()
        defer { lock.unlock() }
        return _removals
    }

    var limit: Int {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _limit
        }
        set {
            lock.lock()
            defer { lock.unlock() }

            _limit = max(0, newValue)

            // `totalCostLimit == 0` means no limit to an `NSCache`, the opposite of off.
            cache.totalCostLimit = max(1, _limit)

            if _limit == 0 {
                _removals += 1
                cache.removeAllObjects()
            }
        }
    }

    /// The image kept for `id`, unless its time is over: that entry is removed and counts as a miss.
    func image(for id: String) -> PlatformImage? {
        guard let entry = cache.object(forKey: id as NSString) else {
            return nil
        }

        if let timeToLive, now().timeIntervalSince(entry.storedAt) >= timeToLive {
            cache.removeObject(forKey: id as NSString)
            return nil
        }

        return entry.image
    }

    /// Keeps `image` for `id`.
    ///
    /// - Parameter removals: The value of ``removals`` when the load that produced `image` began.
    /// When it is not the current one, something was removed since, so the image is dropped
    /// instead of kept. `nil` keeps it whatever happened.
    func insert(_ image: PlatformImage, for id: String, ifRemovalsAre removals: Int? = nil) {
        lock.lock()
        defer { lock.unlock() }

        guard _limit > 0, removals == nil || removals == _removals else {
            return
        }

        cache.setObject(Entry(image, storedAt: now()), forKey: id as NSString, cost: Self.cost(of: image))
    }

    func remove(_ id: String) {
        lock.lock()
        defer { lock.unlock() }

        _removals += 1
        cache.removeObject(forKey: id as NSString)
    }

    func removeAll() {
        lock.lock()
        defer { lock.unlock() }

        _removals += 1
        cache.removeAllObjects()
    }

    /// What the decoded image takes in memory: its pixels, four bytes each. Never `0`, so an
    /// image always counts for something.
    static func cost(of image: PlatformImage) -> Int {
        #if canImport(UIKit)
        let pixels = Double(image.size.width * image.scale) * Double(image.size.height * image.scale)
        #else
        let representation = image.representations.first
        let pixels =
            Double(representation?.pixelsWide ?? Int(image.size.width))
            * Double(representation?.pixelsHigh ?? Int(image.size.height))
        #endif

        guard pixels.isFinite, pixels > 0 else {
            return 1
        }

        return Int(min(pixels * 4, Double(Int.max / 2)))
    }
}

#endif
