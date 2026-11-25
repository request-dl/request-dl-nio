//
// See LICENSE for this package's licensing information.
//

import Foundation
import SwiftAsyncStream
import Testing

@_spi(Private) @testable import RequestDL
@testable import RequestDLTestSupport

#if canImport(UIKit) && !os(watchOS)
import UIKit

@MainActor
struct UIImageViewRequestDLTests {

    /// A real, distinct image: UIKit treats two empty `UIImage()` as equal and may keep the old
    /// instance on assignment, which defeats the identity checks below.
    private static func makeImage(_ color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
    }

    @Test
    func setImageAppliesTheLoadedImage() async throws {
        // Given
        let imageView = UIImageView()
        let signal = AsyncSignal()

        // When
        imageView.rdl.setImage(id: "one", task: StubImageTask { .init(head: .stub, payload: .onePixelPNG) }) { _ in
            signal.signal()
        }
        try await signal.wait()

        // Then
        #expect(imageView.image != nil)
    }

    @Test
    func placeholderIsAppliedImmediately() {
        // Given
        let imageView = UIImageView()
        let placeholder = Self.makeImage(.blue)

        // When
        imageView.rdl.setImage(
            id: "slow",
            task: StubImageTask {
                try await Task.sleep(nanoseconds: 200_000_000)
                return .init(head: .stub, payload: .onePixelPNG)
            },
            placeholder: placeholder
        )

        // Then
        #expect(imageView.image === placeholder)
        imageView.rdl.cancel()
    }

    @Test
    func startingALoadClearsTheCurrentImageWhenThereIsNoPlaceholder() {
        // Given
        let imageView = UIImageView()
        imageView.image = Self.makeImage(.red)

        // When
        imageView.rdl.setImage(
            id: "clears",
            task: StubImageTask {
                try await Task.sleep(nanoseconds: 200_000_000)
                return .init(head: .stub, payload: .onePixelPNG)
            }
        )

        // Then
        #expect(imageView.image == nil)
        imageView.rdl.cancel()
    }

    @Test
    func startingALoadByURLClearsTheCurrentImage() {
        // Given
        let imageView = UIImageView()
        imageView.image = Self.makeImage(.red)

        // When
        imageView.rdl.setImage(with: URL(string: "https://invalid.invalid/image.png")!)

        // Then
        #expect(imageView.image == nil)
        imageView.rdl.cancel()
    }

    @Test
    func placeholderReplacesTheCurrentImage() {
        // Given
        let imageView = UIImageView()
        imageView.image = Self.makeImage(.red)
        let placeholder = Self.makeImage(.blue)

        // When
        imageView.rdl.setImage(
            id: "replaces",
            task: StubImageTask {
                try await Task.sleep(nanoseconds: 200_000_000)
                return .init(head: .stub, payload: .onePixelPNG)
            },
            placeholder: placeholder
        )

        // Then
        #expect(imageView.image === placeholder)
        imageView.rdl.cancel()
    }

    @Test
    func keepingTheCurrentImageLeavesTheViewUntouchedWhileLoading() {
        // Given
        let imageView = UIImageView()
        let current = Self.makeImage(.red)
        imageView.image = current

        // When
        imageView.rdl.setImage(
            id: "keeps",
            task: StubImageTask {
                try await Task.sleep(nanoseconds: 200_000_000)
                return .init(head: .stub, payload: .onePixelPNG)
            },
            placeholder: Self.makeImage(.blue),
            keepsCurrentImageWhileLoading: true
        )

        // Then
        #expect(imageView.image === current)
        imageView.rdl.cancel()
    }

    @Test
    func keepingTheCurrentImageStillShowsThePlaceholderOnAnEmptyView() {
        // Given
        let imageView = UIImageView()
        let placeholder = Self.makeImage(.blue)

        // When
        imageView.rdl.setImage(
            id: "keeps-empty",
            task: StubImageTask {
                try await Task.sleep(nanoseconds: 200_000_000)
                return .init(head: .stub, payload: .onePixelPNG)
            },
            placeholder: placeholder,
            keepsCurrentImageWhileLoading: true
        )

        // Then
        #expect(imageView.image === placeholder)
        imageView.rdl.cancel()
    }

    @Test
    func keepingTheCurrentImageStillAppliesTheLoadedImage() async throws {
        // Given
        let imageView = UIImageView()
        let current = Self.makeImage(.red)
        imageView.image = current
        let signal = AsyncSignal()

        // When
        imageView.rdl.setImage(
            id: "keeps-then-applies",
            task: StubImageTask { .init(head: .stub, payload: .onePixelPNG) },
            keepsCurrentImageWhileLoading: true
        ) { _ in
            signal.signal()
        }
        try await signal.wait()

        // Then
        #expect(imageView.image != nil)
        #expect(imageView.image !== current)
    }

    @Test
    func reusingTheImageViewCancelsThePreviousLoad() async throws {
        // Given
        let imageView = UIImageView()
        let firstCompleted = Flag()
        let secondSignal = AsyncSignal()

        // When
        imageView.rdl.setImage(
            id: "first",
            task: StubImageTask {
                try await Task.sleep(nanoseconds: 300_000_000)
                return .init(head: .stub, payload: .onePixelPNG)
            }
        ) { _ in
            Task { await firstCompleted.set() }
        }

        imageView.rdl.setImage(id: "second", task: StubImageTask { .init(head: .stub, payload: .onePixelPNG) }) { _ in
            secondSignal.signal()
        }

        try await secondSignal.wait()

        // Give the first task's sleep enough time to also finish, to prove its completion never
        // fires once superseded.
        try await Task.sleep(nanoseconds: 500_000_000)

        // Then
        #expect(await !firstCompleted.value)
        #expect(imageView.image != nil)
    }

    @Test
    func cancelStopsThePendingLoad() async throws {
        // Given
        let imageView = UIImageView()
        let completed = Flag()

        // When
        imageView.rdl.setImage(
            id: "cancel-me",
            task: StubImageTask {
                try await Task.sleep(nanoseconds: 200_000_000)
                return .init(head: .stub, payload: .onePixelPNG)
            }
        ) { _ in
            Task { await completed.set() }
        }
        imageView.rdl.cancel()

        try await Task.sleep(nanoseconds: 400_000_000)

        // Then
        #expect(await !completed.value)
    }

    /// The completion not firing is not the same as the request being stopped: a cell that is
    /// reused has to free the connection of the image it no longer shows.
    @Test
    func reusingTheImageViewInterruptsTheRequestOfThePreviousLoad() async throws {
        // Given
        let imageView = UIImageView()
        let started = Flag()
        let interrupted = Flag()

        imageView.rdl.setImage(
            id: "interrupted-by-reuse-\(UUID())",
            task: StubImageTask {
                await started.set()

                do {
                    try await Task.sleep(nanoseconds: 60_000_000_000)
                } catch {
                    await interrupted.set()
                    throw error
                }

                return .init(head: .stub, payload: .onePixelPNG)
            }
        )

        try await eventually { await started.value }

        // When
        imageView.rdl.setImage(
            id: "replacement-\(UUID())",
            task: StubImageTask { .init(head: .stub, payload: .onePixelPNG) }
        )

        // Then
        try await eventually { await interrupted.value }
    }

    @Test
    func cancelInterruptsTheRequestOfThePendingLoad() async throws {
        // Given
        let imageView = UIImageView()
        let started = Flag()
        let interrupted = Flag()

        imageView.rdl.setImage(
            id: "interrupted-by-cancel-\(UUID())",
            task: StubImageTask {
                await started.set()

                do {
                    try await Task.sleep(nanoseconds: 60_000_000_000)
                } catch {
                    await interrupted.set()
                    throw error
                }

                return .init(head: .stub, payload: .onePixelPNG)
            }
        )

        try await eventually { await started.value }

        // When
        imageView.rdl.cancel()

        // Then
        try await eventually { await interrupted.value }
    }
    // MARK: - Images already in memory

    private static func warmedLoader(id: String) async throws -> (loader: RDLImageLoader, image: UIImage) {
        let loader = RDLImageLoader()
        let image = try await loader.load(id: id, task: StubImageTask { .init(head: .stub, payload: .onePixelPNG) })
        return (loader, image)
    }

    private static func slow(_ nanoseconds: UInt64 = 300_000_000) -> StubImageTask {
        StubImageTask {
            try await Task.sleep(nanoseconds: nanoseconds)
            return .init(head: .stub, payload: .onePixelPNG)
        }
    }

    /// The case the memory cache is for: a cell comes back to an image it already showed. The view
    /// has to hold that image in the same turn, not an empty frame first.
    @Test
    func anImageInMemoryIsShownAtOnceInsteadOfClearingTheView() async throws {
        // Given
        let (loader, cached) = try await Self.warmedLoader(id: "warm")
        let imageView = UIImageView()
        imageView.image = Self.makeImage(.red)

        // When
        imageView.rdl.setImage(id: "warm", task: Self.slow(), placeholder: Self.makeImage(.blue), loader: loader)

        // Then
        #expect(imageView.image === cached)
        imageView.rdl.cancel()
    }

    @Test
    func anImageInMemoryIsShownAtOnceForALoadByURL() async throws {
        // Given
        let url = URL(string: "https://invalid.invalid/warm.png")!
        let loader = RDLImageLoader()
        let cached = try await loader.load(
            id: url.absoluteString,
            task: StubImageTask { .init(head: .stub, payload: .onePixelPNG) }
        )
        let imageView = UIImageView()

        // When
        imageView.rdl.setImage(with: url, loader: loader)

        // Then
        #expect(loader.cachedImage(url: url) === cached)
        #expect(imageView.image === cached)
        imageView.rdl.cancel()
    }

    @Test
    func anImageInMemoryIsShownEvenWhenKeepingTheCurrentImageOfAnotherView() async throws {
        // Given
        let (loader, cached) = try await Self.warmedLoader(id: "warm-keeps")
        let imageView = UIImageView()
        imageView.image = Self.makeImage(.red)

        // When
        imageView.rdl.setImage(id: "warm-keeps", task: Self.slow(), loader: loader, keepsCurrentImageWhileLoading: true)

        // Then
        #expect(imageView.image === cached)
        imageView.rdl.cancel()
    }

    /// The copy in memory only shows something sooner: the request still runs, with whatever it
    /// says, and its result replaces the copy.
    @Test
    func anImageInMemoryDoesNotStandInForTheRequest() async throws {
        // Given
        let (loader, cached) = try await Self.warmedLoader(id: "warm-runs")
        let imageView = UIImageView()
        let signal = AsyncSignal()
        let ran = Flag()

        // When
        imageView.rdl.setImage(
            id: "warm-runs",
            task: StubImageTask {
                await ran.set()
                return .init(head: .stub, payload: .onePixelPNG)
            },
            loader: loader
        ) { _ in
            signal.signal()
        }

        #expect(imageView.image === cached)
        try await signal.wait()

        // Then
        #expect(await ran.value)
        #expect(imageView.image != nil)
        #expect(imageView.image !== cached)
        #expect(loader.cachedImage(id: "warm-runs") !== cached)
    }

    @Test
    func anImageInMemoryForAnotherIDDoesNotShowUp() async throws {
        // Given
        let (loader, _) = try await Self.warmedLoader(id: "warm-other")
        let imageView = UIImageView()
        imageView.image = Self.makeImage(.red)

        // When
        imageView.rdl.setImage(id: "not-warm", task: Self.slow(), loader: loader)

        // Then
        #expect(imageView.image == nil)
        imageView.rdl.cancel()
    }

    @Test
    func removingTheImageInMemoryBringsBackClearingTheView() async throws {
        // Given
        let (loader, _) = try await Self.warmedLoader(id: "warm-removed")
        loader.removeCachedImage(id: "warm-removed")
        let imageView = UIImageView()
        imageView.image = Self.makeImage(.red)
        let placeholder = Self.makeImage(.blue)

        // When
        imageView.rdl.setImage(id: "warm-removed", task: Self.slow(), placeholder: placeholder, loader: loader)

        // Then
        #expect(imageView.image === placeholder)
        imageView.rdl.cancel()
    }

    @Test
    func aLoaderWithoutAMemoryCacheKeepsClearingTheView() async throws {
        // Given
        let loader = RDLImageLoader(dataCache: DataCache(suiteName: UUID().uuidString), memoryCacheLimit: 0)
        _ = try await loader.load(id: "off", task: StubImageTask { .init(head: .stub, payload: .onePixelPNG) })
        let imageView = UIImageView()
        imageView.image = Self.makeImage(.red)

        // When
        imageView.rdl.setImage(id: "off", task: Self.slow(), loader: loader)

        // Then
        #expect(loader.cachedImage(id: "off") == nil)
        #expect(imageView.image == nil)
        imageView.rdl.cancel()
    }

    /// Reusing the view for another image cancels the load of the one it showed, and the image of
    /// that load, which was put on screen at once, does not come back when its request ends late.
    @Test
    func reusingAViewShowingAnImageInMemoryNeverBringsItBack() async throws {
        // Given
        let (loader, cached) = try await Self.warmedLoader(id: "warm-first")
        let imageView = UIImageView()
        let firstCompleted = Flag()
        let secondSignal = AsyncSignal()

        imageView.rdl.setImage(id: "warm-first", task: Self.slow(), loader: loader) { _ in
            Task { await firstCompleted.set() }
        }
        #expect(imageView.image === cached)

        // When
        imageView.rdl.setImage(
            id: "second",
            task: StubImageTask { .init(head: .stub, payload: .onePixelPNG) },
            loader: loader
        ) { _ in
            secondSignal.signal()
        }

        // Then
        #expect(imageView.image == nil)
        try await secondSignal.wait()
        try await Task.sleep(nanoseconds: 500_000_000)

        #expect(await !firstCompleted.value)
        #expect(imageView.image != nil)
        #expect(imageView.image !== cached)
    }

    /// Two loads race for one view, and the one started last is the one that arrives first.
    @Test
    func theLastLoadStartedWinsWhenTheEarlierOneArrivesAfterIt() async throws {
        // Given
        let loader = RDLImageLoader()
        let imageView = UIImageView()
        let firstCompleted = Flag()
        let secondSignal = AsyncSignal()

        // When
        imageView.rdl.setImage(id: "race-first", task: Self.slow(400_000_000), loader: loader) { _ in
            Task { await firstCompleted.set() }
        }
        imageView.rdl.setImage(
            id: "race-second",
            task: StubImageTask { .init(head: .stub, payload: .onePixelPNG) },
            loader: loader
        ) { _ in
            secondSignal.signal()
        }

        try await secondSignal.wait()
        let shown = imageView.image
        try await Task.sleep(nanoseconds: 600_000_000)

        // Then
        #expect(shown != nil)
        #expect(imageView.image === shown)
        #expect(await !firstCompleted.value)
        #expect(loader.cachedImage(id: "race-second") != nil)
        #expect(loader.cachedImage(id: "race-first") == nil)
    }
    // MARK: - A URL in memory is not requested

    /// Nothing listens there, so a request would end in a refused connection and say so to the
    /// completion: that nothing arrives is how these tests know there was none.
    private static let unreachable = URL(string: "http://127.0.0.1:1/avatar.png")!

    private static func warmedLoader(
        url: URL,
        timeToLive: TimeInterval? = 300
    ) async throws -> (loader: RDLImageLoader, image: UIImage) {
        let loader = RDLImageLoader(
            dataCache: DataCache(suiteName: UUID().uuidString),
            memoryCacheLimit: 1_024 * 1_024,
            memoryCacheTimeToLive: timeToLive
        )

        let image = try await loader.load(
            id: url.absoluteString,
            task: StubImageTask { .init(head: .stub, payload: .onePixelPNG) }
        )

        return (loader, image)
    }

    @Test
    func aURLInMemoryIsShownAndCompletedAtOnceWithoutARequest() async throws {
        // Given
        let (loader, cached) = try await Self.warmedLoader(url: Self.unreachable)
        let imageView = UIImageView()
        imageView.image = Self.makeImage(.red)
        let results = LockedValueBox<[Result<UIImage, Error>]>([])

        // When
        imageView.rdl.setImage(with: Self.unreachable, loader: loader) { result in
            results.withLockedValue { $0.append(result) }
        }

        // Then: before the method's caller has run again
        #expect(imageView.image === cached)
        #expect(results.withLockedValue { $0 }.count == 1)
        #expect(try results.withLockedValue { $0 }[0].get() === cached)
        #expect(await loader.waiterCountForTesting(id: Self.unreachable.absoluteString) == 0)

        // A request would have failed by now, and said so.
        try await Task.sleep(nanoseconds: 400_000_000)
        #expect(results.withLockedValue { $0 }.count == 1)
        #expect(imageView.image === cached)
    }

    @Test
    func refreshingShowsTheURLInMemoryAndMakesTheRequestAnyway() async throws {
        // Given
        let (loader, cached) = try await Self.warmedLoader(url: Self.unreachable)
        let imageView = UIImageView()
        let results = LockedValueBox<[Result<UIImage, Error>]>([])

        // When
        imageView.rdl.setImage(with: Self.unreachable, loader: loader, refreshing: true) { result in
            results.withLockedValue { $0.append(result) }
        }

        // Then
        #expect(imageView.image === cached)
        #expect(results.withLockedValue { $0 }.isEmpty)

        try await eventually { results.withLockedValue { $0 }.count == 1 }

        // The request failed, and what was on screen stays.
        if case .success = results.withLockedValue({ $0 })[0] {
            Issue.record("The request was expected to fail")
        }
        #expect(imageView.image === cached)
        #expect(loader.cachedImage(url: Self.unreachable) === cached)
    }

    @Test
    func anExpiredURLInMemoryIsAMissAndRunsTheRequest() async throws {
        // Given
        let (loader, _) = try await Self.warmedLoader(url: Self.unreachable, timeToLive: 0.05)
        try await Task.sleep(nanoseconds: 150_000_000)
        let imageView = UIImageView()
        imageView.image = Self.makeImage(.red)
        let results = LockedValueBox<[Result<UIImage, Error>]>([])

        // When
        imageView.rdl.setImage(with: Self.unreachable, loader: loader) { result in
            results.withLockedValue { $0.append(result) }
        }

        // Then
        #expect(imageView.image == nil)
        #expect(loader.cachedImage(url: Self.unreachable) == nil)

        try await eventually { results.withLockedValue { $0 }.count == 1 }
    }

    @Test
    func withoutATimeToLiveAURLInMemoryDoesNotExpire() async throws {
        // Given
        let (loader, cached) = try await Self.warmedLoader(url: Self.unreachable, timeToLive: nil)
        try await Task.sleep(nanoseconds: 150_000_000)
        let imageView = UIImageView()

        // When
        imageView.rdl.setImage(with: Self.unreachable, loader: loader)

        // Then
        #expect(imageView.image === cached)
    }

    @Test
    func removingTheURLFromMemoryMakesTheNextCallRunTheRequest() async throws {
        // Given
        let (loader, _) = try await Self.warmedLoader(url: Self.unreachable)
        loader.removeCachedImage(url: Self.unreachable)
        let imageView = UIImageView()
        let results = LockedValueBox<[Result<UIImage, Error>]>([])

        // When
        imageView.rdl.setImage(with: Self.unreachable, loader: loader) { result in
            results.withLockedValue { $0.append(result) }
        }

        // Then
        #expect(imageView.image == nil)
        try await eventually { results.withLockedValue { $0 }.count == 1 }
    }

    /// The variant with a task is the caller's: its policy, headers and credentials, and its own
    /// key. A copy in memory is shown first and the request runs, whatever the copy's age.
    @Test
    func aTaskAlwaysRunsItsRequestEvenWithAValidImageInMemory() async throws {
        // Given
        let (loader, cached) = try await Self.warmedLoader(url: URL(string: "https://example.com/account-a.png")!)
        let imageView = UIImageView()
        let ran = Flag()
        let signal = AsyncSignal()

        // When
        imageView.rdl.setImage(
            id: "https://example.com/account-a.png",
            task: StubImageTask {
                await ran.set()
                return .init(head: .stub, payload: .onePixelPNG)
            },
            loader: loader
        ) { _ in
            signal.signal()
        }

        #expect(imageView.image === cached)
        try await signal.wait()

        // Then
        #expect(await ran.value)
    }
}

// MARK: - Test helpers

private struct StubImageTask: RequestTask {

    let onResult: @Sendable () async throws -> TaskResult<Data>

    func result() async throws -> TaskResult<Data> {
        try await onResult()
    }
}

private actor Flag {

    private(set) var value = false

    func set() {
        value = true
    }
}

extension ResponseHead {

    fileprivate static let stub = ResponseHead(
        url: nil,
        status: .init(code: 200, reason: "OK"),
        version: .init(minor: 1, major: 1),
        headers: HTTPHeaders(),
        isKeepAlive: false
    )
}

extension Data {

    fileprivate static let onePixelPNG = Data(
        base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    )!
}
#endif
