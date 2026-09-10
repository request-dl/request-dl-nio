//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL

/// Regression coverage for `HeaderNode.singleValuedNames`: `Host`, `Origin`, `Referer`,
/// `Authorization`, `Content-Type`, and `Content-Length` must always overwrite, never combine or
/// duplicate, no matter what `.headerStrategy`/`.headerSeparator` is in scope or which `Property`
/// produced the colliding write.
///
/// Two failure modes existed before this fix, both reproduced here:
/// - No separator in scope: `.adding` fell through to `headers.add(...)`, leaving two raw values
///   on the same logical entry. For a header a server or client is only allowed to see once
///   (RFC 9110 §7.2 mandates a 400 for a duplicate `Host`, for instance), that reaches the wire
///   as either two field lines or a client-coalesced single line, neither of them what any of
///   these headers' own grammar defines.
/// - A separator in scope: `.adding` spliced the new value directly into whatever was already
///   there, producing one *corrupted* string (e.g. a `Content-Type` reading
///   `"application/json; charset=UTF-8,application/xml"`) that fails to parse as anything valid
///   at all: strictly worse than the no-separator case, since even the original value is lost.
struct HeaderNodeSingleValuedNamesTests {

    // MARK: - Same property declared twice

    @Test
    func host_whenDeclaredTwiceUnderAddingStrategy_overwritesInsteadOfCombining() async throws {
        // Given
        let resolved = try await resolve(
            TestProperty {
                HeaderGroup {
                    HostHeader("first.example.com")
                    HostHeader("second.example.com")
                }
                .headerStrategy(.adding)
            }
        )

        // Then, per RFC 9110 §7.2: a server MUST 400 a request carrying more than one Host field.
        #expect(resolved.requestConfiguration.headers["Host"] == ["second.example.com"])
    }

    @Test
    func origin_whenDeclaredTwiceUnderAddingStrategy_overwritesInsteadOfCombining() async throws {
        // Given
        let resolved = try await resolve(
            TestProperty {
                HeaderGroup {
                    OriginHeader("https://first.example.com")
                    OriginHeader("https://second.example.com")
                }
                .headerStrategy(.adding)
            }
        )

        // Then: a single serialized origin (RFC 6454/Fetch), never a list.
        #expect(resolved.requestConfiguration.headers["Origin"] == ["https://second.example.com"])
    }

    @Test
    func referer_whenDeclaredTwiceUnderAddingStrategy_overwritesInsteadOfCombining() async throws {
        // Given
        let resolved = try await resolve(
            TestProperty {
                HeaderGroup {
                    RefererHeader("https://first.example.com/")
                    RefererHeader("https://second.example.com/")
                }
                .headerStrategy(.adding)
            }
        )

        // Then: a single URI-reference (RFC 9110 §10.1.3), never a list.
        #expect(resolved.requestConfiguration.headers["Referer"] == ["https://second.example.com/"])
    }

    // MARK: - Collision with an unrelated `CustomHeader`, no separator in scope

    @Test
    func host_whenCollidingWithDifferentlyCasedCustomHeader_overwritesWithoutDuplicating() async throws {
        // Given
        let resolved = try await resolve(
            TestProperty {
                HostHeader("original.example.com")
                CustomHeader(name: "host", value: "collided.example.com")
            }
        )

        // Then: a plain `.add()` would have left two raw values instead of one.
        #expect(resolved.requestConfiguration.headers["Host"] == ["collided.example.com"])
    }

    @Test
    func authorization_whenCollidingWithDifferentlyCasedCustomHeader_overwritesWithoutDuplicating() async throws {
        // Given: `Authorization` writes via a direct `headers.set(...)`, bypassing `HeaderNode`
        // entirely; that alone doesn't stop a later `CustomHeader` from appending onto it.
        let resolved = try await resolve(
            TestProperty {
                Authorization(.bearer, token: "original-token")
                CustomHeader(name: "authorization", value: "Bearer collided-token")
            }
        )

        #expect(resolved.requestConfiguration.headers["Authorization"] == ["Bearer collided-token"])
    }

    // MARK: - Collision with an unrelated `CustomHeader`, explicit separator in scope

    @Test
    func host_whenCollidingWithCustomHeaderUnderExplicitSeparator_overwritesWithoutCorrupting() async throws {
        // Given (the sharper failure mode): with a separator in scope, `.adding` used to splice
        // the new value directly into the existing one instead of just duplicating it.
        let resolved = try await resolve(
            TestProperty {
                HostHeader("original.example.com")
                CustomHeader(name: "host", value: "collided.example.com")
                    .headerStrategy(.adding)
                    .headerSeparator(",")
            }
        )

        #expect(resolved.requestConfiguration.headers["Host"] == ["collided.example.com"])
    }

    @Test
    func contentType_whenCollidingWithCustomHeaderUnderExplicitSeparator_overwritesWithoutCorrupting() async throws {
        // Given (the exact scenario that motivated this fix): `Payload` sets `Content-Type` via
        // a direct `.set()`, then a colliding `CustomHeader` with a separator in scope used to
        // splice its value directly into it, producing an unparseable single string
        // ("application/json; charset=UTF-8,application/xml").
        let resolved = try await resolve(
            TestProperty {
                Payload(verbatim: "test", contentType: .json)

                CustomHeader(name: "content-type", value: "application/xml")
                    .headerStrategy(.adding)
                    .headerSeparator(",")
            }
        )

        // Then: one valid value, not a garbled concatenation of both.
        #expect(resolved.requestConfiguration.headers["Content-Type"] == ["application/xml"])
    }
}
