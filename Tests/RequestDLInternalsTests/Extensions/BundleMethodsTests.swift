//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDLInternals

#if canImport(Darwin)
import class Foundation.Bundle
import struct Foundation.URL

struct BundleMethodsTests {

    @Test
    func resolveURLWithEmptyNameFindsNothing() {
        // When
        let resolved = Bundle.module.resolveURL(forResourceName: "")

        // Then
        #expect(resolved == nil)
    }

    @Test
    func resolveURLWithSubdirectoryAndNoExtensionFindsNothing() {
        // When
        // No dot in the last path component, and a slash ahead of it: exercises both the
        // "no extension" and "has a subdirectory" branches of the private `resolve(name:)`
        // splitter at once. Nothing in the resources tree matches, which is fine — only the
        // splitting logic itself is under test here.
        let resolved = Bundle.module.resolveURL(forResourceName: "some-directory/no-extension-name")

        // Then
        #expect(resolved == nil)
    }

    @Test
    func normalizedResourceURLUsesResourceURLWhenAvailable() {
        // Given
        // Every `Bundle` this process can actually construct reports a `resourceURL` on
        // current Darwin Foundation — even a directory with no real bundle structure falls
        // back to `bundleURL` internally rather than reporting `nil` (confirmed against both
        // `Bundle.module` and a `Bundle(url:)` over an arbitrary directory). The `else` branch
        // of `normalizedResourceURL`, for a bundle whose own `resourceURL` is `nil`, is
        // therefore not reachable from a test: `Bundle(url:)` itself returns `nil` — no
        // instance to call the property on — for the one case (a genuinely nonexistent path)
        // that comes close.
        let bundle = Bundle.module

        // Then
        #expect(bundle.resourceURL != nil)
        #expect(bundle.normalizedResourceURL == bundle.resourceURL)
    }
}
#endif
