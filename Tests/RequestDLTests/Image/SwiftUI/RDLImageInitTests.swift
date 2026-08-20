//
// See LICENSE for this package's licensing information.
//

import Foundation
import SwiftUI
import Testing

@testable import RequestDL

#if canImport(SwiftUI) && (canImport(UIKit) || canImport(AppKit))
/// `RDLImage` leans on `_ConditionalContent`-returning generic initializers to mirror
/// `AsyncImage`'s API. That machinery is easy to break silently — the type still compiles, just
/// against a narrower or looser signature than intended — so these tests exist to pin every
/// public initializer's shape, not to exercise runtime loading behavior (already covered by
/// `RDLImageLoaderTests`).
@MainActor
struct RDLImageInitTests {

    private static let url = URL(string: "https://example.com/avatar.png")

    @Test
    func urlPhaseInit() {
        // When
        let view = RDLImage(url: Self.url) { (_: RDLImagePhase) in
            EmptyView()
        }

        // Then
        #expect(type(of: view) == RDLImage<EmptyView>.self)
    }

    @Test
    func nilURLPhaseInit() {
        // When
        let view = RDLImage(url: nil) { (_: RDLImagePhase) in
            EmptyView()
        }

        // Then
        #expect(type(of: view) == RDLImage<EmptyView>.self)
    }

    @Test
    func urlContentPlaceholderInit() {
        // When/Then
        _ = RDLImage(
            url: Self.url,
            content: { $0.resizable() },
            placeholder: { ProgressView() }
        )
    }

    @Test
    func taskPhaseInit() {
        // Given
        // `Path` is qualified because `SwiftUI` also declares a `Path` type (the vector graphics
        // one), and this file imports both.
        let task = DataTask {
            BaseURL("example.com")
            RequestDL.Path("avatar.png")
        }

        // When/Then
        _ = RDLImage(id: "avatar", task: task) { (_: RDLImagePhase) in
            EmptyView()
        }
    }
}
#endif
