//
// See LICENSE for this package's licensing information.
//

import Foundation
import SwiftAsyncStream
import Testing

@testable import RequestDL

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit

@MainActor
struct NSImageViewRequestDLTests {

    @Test
    func setImageAppliesTheLoadedImage() async throws {
        // Given
        let imageView = NSImageView()
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
        let imageView = NSImageView()
        let placeholder = NSImage()

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
    func reusingTheImageViewCancelsThePreviousLoad() async throws {
        // Given
        let imageView = NSImageView()
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
        let imageView = NSImageView()
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
