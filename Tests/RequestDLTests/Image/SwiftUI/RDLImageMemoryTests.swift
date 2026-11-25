//
// See LICENSE for this package's licensing information.
//

import Foundation
import Testing

@_spi(Private) @testable import RequestDL
@testable import RequestDLTestSupport

#if canImport(SwiftUI) && (canImport(UIKit) || canImport(AppKit))
import SwiftUI

/// What `RDLImage` starts with when the loader has the image in memory: the same frame the view
/// is created in already shows it, and for a URL no request is made.
@MainActor
struct RDLImageMemoryTests {

    private static let url = URL(string: "https://example.com/avatar.png")!
    private static let otherURL = URL(string: "https://example.com/other.png")!

    private static func makeLoader(timeToLive: TimeInterval? = 300) -> RDLImageLoader {
        RDLImageLoader(
            dataCache: DataCache(suiteName: UUID().uuidString),
            memoryCacheLimit: 1_024 * 1_024,
            memoryCacheTimeToLive: timeToLive
        )
    }

    private static func warm(_ loader: RDLImageLoader, id: String) async throws {
        _ = try await loader.load(id: id, task: StubImageTask { .init(head: .stub, payload: .onePixelPNG) })
    }

    // MARK: - The plan

    @Test
    func plan_forAURLInMemory_isTheImageAndNoRequest() async throws {
        let loader = Self.makeLoader()
        try await Self.warm(loader, id: Self.url.absoluteString)

        let plan = RDLImage<EmptyView>.plan(for: .url(Self.url), loader: loader, scale: 1)

        #expect(plan.phase.image != nil)
        #expect(plan.isCached)
        #expect(!plan.runsRequest)
    }

    @Test
    func plan_forAURLNotInMemory_isEmptyAndTheRequest() {
        let plan = RDLImage<EmptyView>.plan(for: .url(Self.url), loader: Self.makeLoader(), scale: 1)

        #expect(plan.phase.image == nil)
        #expect(plan.phase.error == nil)
        #expect(!plan.isCached)
        #expect(plan.runsRequest)
    }

    /// `refreshing` keeps the copy as the first phase, marks it as one (so a failed request leaves it
    /// on screen) and makes the request.
    @Test
    func plan_forAURLInMemory_whenRefreshing_isTheImageAndTheRequestRuns() async throws {
        let loader = Self.makeLoader()
        try await Self.warm(loader, id: Self.url.absoluteString)

        let plan = RDLImage<EmptyView>.plan(for: .url(Self.url), loader: loader, scale: 1, refreshing: true)

        #expect(plan.phase.image != nil)
        #expect(plan.isCached)
        #expect(plan.runsRequest)
    }

    @Test
    func plan_forAURLNotInMemory_whenRefreshing_isEmptyAndTheRequest() {
        let plan = RDLImage<EmptyView>.plan(
            for: .url(Self.url),
            loader: Self.makeLoader(),
            scale: 1,
            refreshing: true
        )

        #expect(plan.phase.image == nil)
        #expect(!plan.isCached)
        #expect(plan.runsRequest)
    }

    @Test
    func plan_withoutAKey_whenRefreshing_stillMakesNoRequest() {
        let plan = RDLImage<EmptyView>.plan(for: nil, loader: Self.makeLoader(), scale: 1, refreshing: true)

        #expect(plan.phase.image == nil)
        #expect(!plan.runsRequest)
    }

    @Test
    func plan_forAnIDInMemory_isTheImageAndTheRequestStillRuns() async throws {
        let loader = Self.makeLoader()
        try await Self.warm(loader, id: "avatar")

        let plan = RDLImage<EmptyView>.plan(for: .id("avatar"), loader: loader, scale: 1)

        #expect(plan.phase.image != nil)
        #expect(plan.isCached)
        #expect(plan.runsRequest)
    }

    @Test
    func plan_forAnIDNotInMemory_isEmptyAndTheRequest() async throws {
        let loader = Self.makeLoader()
        try await Self.warm(loader, id: "avatar")

        let plan = RDLImage<EmptyView>.plan(for: .id("another"), loader: loader, scale: 1)

        #expect(plan.phase.image == nil)
        #expect(!plan.isCached)
        #expect(plan.runsRequest)
    }

    @Test
    func plan_withoutAKey_isEmptyAndNoRequest() {
        let plan = RDLImage<EmptyView>.plan(for: nil, loader: Self.makeLoader(), scale: 1)

        #expect(plan.phase.image == nil)
        #expect(!plan.runsRequest)
    }

    @Test
    func plan_forAnExpiredImage_isAMiss() async throws {
        let loader = Self.makeLoader(timeToLive: 0.05)
        try await Self.warm(loader, id: Self.url.absoluteString)
        try await Task.sleep(nanoseconds: 150_000_000)

        let plan = RDLImage<EmptyView>.plan(for: .url(Self.url), loader: loader, scale: 1)

        #expect(plan.phase.image == nil)
        #expect(plan.runsRequest)
    }

    /// A view whose URL changes keeps its state, so what it starts with is decided again.
    @Test
    func plan_whenTheURLChanges_followsTheNewOne() async throws {
        let loader = Self.makeLoader()
        try await Self.warm(loader, id: Self.url.absoluteString)

        let first = RDLImage<EmptyView>.plan(for: .url(Self.url), loader: loader, scale: 1)
        let second = RDLImage<EmptyView>.plan(for: .url(Self.otherURL), loader: loader, scale: 1)

        #expect(first.phase.image != nil && !first.runsRequest)
        #expect(second.phase.image == nil && second.runsRequest)
    }

    // MARK: - The first body

    private final class Phases: @unchecked Sendable {
        private let lock = NSLock()
        private var _phases: [RDLImagePhase] = []

        var all: [RDLImagePhase] {
            lock.lock()
            defer { lock.unlock() }
            return _phases
        }

        func record(_ phase: RDLImagePhase) {
            lock.lock()
            defer { lock.unlock() }
            _phases.append(phase)
        }
    }

    private func render<V: View>(_ view: V) {
        let renderer = ImageRenderer(content: view.frame(width: 4, height: 4))
        #if canImport(UIKit)
        _ = renderer.uiImage
        #else
        _ = renderer.nsImage
        #endif
    }

    @Test
    func firstBody_withTheURLInMemory_isAlreadyASuccess() async throws {
        let loader = Self.makeLoader()
        try await Self.warm(loader, id: Self.url.absoluteString)
        let phases = Phases()

        render(
            RDLImage(url: Self.url, loader: loader) { phase -> Color in
                phases.record(phase)
                return .clear
            }
        )

        let first = try #require(phases.all.first)
        #expect(first.image != nil)
    }

    @Test
    func firstBody_withTheURLInMemory_whenRefreshing_isAlreadyASuccess() async throws {
        let loader = Self.makeLoader()
        try await Self.warm(loader, id: Self.url.absoluteString)
        let phases = Phases()

        render(
            RDLImage(url: Self.url, loader: loader, refreshing: true) { phase -> Color in
                phases.record(phase)
                return .clear
            }
        )

        let first = try #require(phases.all.first)
        #expect(first.image != nil)
    }

    /// The content/placeholder convenience init forwards `refreshing`, and keeps compiling without it.
    @Test
    func convenienceInit_acceptsRefreshing_andShowsTheCopyFirst() async throws {
        let loader = Self.makeLoader()
        try await Self.warm(loader, id: Self.url.absoluteString)
        let shown = Phases()

        render(
            RDLImage(url: Self.url, loader: loader, refreshing: true) { image -> Color in
                shown.record(.success(image))
                return Color.clear
            } placeholder: {
                Color.red
            }
        )
        render(
            RDLImage(url: Self.url, loader: loader) { _ -> Color in
                Color.clear
            } placeholder: {
                Color.red
            }
        )

        #expect(shown.all.first?.image != nil)
    }

    @Test
    func firstBody_withTheIDInMemory_isAlreadyASuccess() async throws {
        let loader = Self.makeLoader()
        try await Self.warm(loader, id: "avatar")
        let phases = Phases()

        render(
            RDLImage(
                id: "avatar",
                loader: loader,
                task: StubImageTask { .init(head: .stub, payload: .onePixelPNG) }
            ) { phase -> Color in
                phases.record(phase)
                return .clear
            }
        )

        let first = try #require(phases.all.first)
        #expect(first.image != nil)
    }

    @Test
    func firstBody_withoutAnImageInMemory_isEmpty() {
        let phases = Phases()

        render(
            RDLImage(url: Self.url, loader: Self.makeLoader()) { phase -> Color in
                phases.record(phase)
                return .clear
            }
        )

        let first = phases.all.first
        #expect(first != nil)
        #expect(first?.image == nil)
        #expect(first?.error == nil)
    }
}

private struct StubImageTask: RequestTask {

    let onResult: @Sendable () async throws -> TaskResult<Data>

    func result() async throws -> TaskResult<Data> {
        try await onResult()
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
