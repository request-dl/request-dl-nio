//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL

/// Regression coverage for `HeaderNode.commaSeparatedNames`: `Accept`, `Accept-Charset`,
/// `Accept-Encoding`, `Accept-Language`, and `Cache-Control` must always combine with `,`, no
/// matter what `.headerSeparator(_:)` is in scope: RFC 9110/9111 define each of these as a
/// comma-separated list, and `;` in particular already means something inside the `Accept-*`
/// family's own grammar (`q` parameters), so honoring an arbitrary separator there wouldn't just
/// be non-standard, it would actively misparse.
struct HeaderNodeCommaSeparatedNamesTests {

    // MARK: - Same property declared twice, non-comma separator in scope

    @Test
    func accept_whenCombinedUnderNonCommaSeparator_forcesComma() async throws {
        // Given: `;` already separates a media-range from its own `q` parameter; joining two
        // instances with it instead of `,` would misparse the second value as a parameter of the
        // first.
        let resolved = try await resolve(
            TestProperty {
                HeaderGroup {
                    AcceptHeader(.json)
                    AcceptHeader(.jpeg)
                }
                .headerStrategy(.adding)
                .headerSeparator(";")
            }
        )

        #expect(resolved.requestConfiguration.headers["Accept"] == ["application/json,image/jpeg"])
    }

    @Test
    func cacheControl_whenCombinedUnderNonCommaSeparator_forcesComma() async throws {
        // Given
        let resolved = try await resolve(
            TestProperty {
                HeaderGroup {
                    CacheHeader().stored(false)
                    CacheHeader().cached(false)
                }
                .headerStrategy(.adding)
                .headerSeparator(";")
            }
        )

        // Then, per RFC 9111 §5.2: `1#cache-directive` is comma-delimited; joined with anything
        // else it would parse as one opaque, unrecognized directive.
        #expect(resolved.requestConfiguration.headers["Cache-Control"] == ["no-store,no-cache"])
    }

    // MARK: - A single instance's own internal directive list

    @Test
    func cacheControl_whenHeaderSeparatorOverridden_stillJoinsOwnDirectivesWithComma() async throws {
        // Given: a single `CacheHeader` instance joins its *own* multiple directives before
        // `HeaderNode` is ever involved, so this exercises `CacheHeader`'s own hardcoded `,`
        // rather than `HeaderNode.commaSeparatedNames`.
        let resolved = try await resolve(
            TestProperty {
                CacheHeader()
                    .cached(false)
                    .stored(false)
            }
            .headerSeparator(";")
        )

        #expect(resolved.requestConfiguration.headers["Cache-Control"] == ["no-cache,no-store"])
    }

    // MARK: - Collision with an unrelated `CustomHeader`, non-comma separator in scope

    @Test
    func acceptEncoding_whenCollidingWithCustomHeaderUnderNonCommaSeparator_forcesComma() async throws {
        // Given
        let resolved = try await resolve(
            TestProperty {
                AcceptEncodingHeader(.gzip)
                CustomHeader(name: "accept-encoding", value: "br")
                    .headerStrategy(.adding)
                    .headerSeparator(";")
            }
        )

        #expect(resolved.requestConfiguration.headers["Accept-Encoding"] == ["gzip;q=1.0,br"])
    }

    // MARK: - Control: an unrelated `CustomHeader` name keeps its own configured separator

    @Test
    func customHeader_whenCombinedUnderNonCommaSeparator_keepsItsOwnSeparator() async throws {
        // Given: an arbitrary header name RequestDL doesn't define the semantics of; forcing
        // comma here would be an overreach `commaSeparatedNames` deliberately doesn't make.
        let resolved = try await resolve(
            TestProperty {
                HeaderGroup {
                    CustomHeader(name: "x-tags", value: "a")
                    CustomHeader(name: "x-tags", value: "b")
                }
                .headerStrategy(.adding)
                .headerSeparator(";")
            }
        )

        #expect(resolved.requestConfiguration.headers["x-tags"] == ["a;b"])
    }
}
