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
final class RDLImageMemoryCache: @unchecked Sendable {

    /// What a loader keeps when it is not told otherwise: room for a few dozen thumbnails or a few
    /// full-screen images.
    static let defaultLimit = 64 * 1_024 * 1_024

    private final class Entry {
        let image: PlatformImage

        init(_ image: PlatformImage) {
            self.image = image
        }
    }

    private let cache = NSCache<NSString, Entry>()
    private let lock = NSLock()
    private var _limit = 0

    init(limit: Int) {
        self.limit = limit
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
                cache.removeAllObjects()
            }
        }
    }

    func image(for id: String) -> PlatformImage? {
        cache.object(forKey: id as NSString)?.image
    }

    func insert(_ image: PlatformImage, for id: String) {
        guard limit > 0 else {
            return
        }

        cache.setObject(Entry(image), forKey: id as NSString, cost: Self.cost(of: image))
    }

    func remove(_ id: String) {
        cache.removeObject(forKey: id as NSString)
    }

    func removeAll() {
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
