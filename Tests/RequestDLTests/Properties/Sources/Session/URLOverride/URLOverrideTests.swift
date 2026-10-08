//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL

struct URLOverrideTests {

    @Test
    func hostOnlyOverride() async throws {
        // Given / When
        let resolved = try await resolve(
            TestProperty {
                BaseURL("google.com")
                URLOverride("https://apple.com", from: "https://google.com")
            }
        )

        // Then
        #expect(resolved.requestConfiguration.url == "https://apple.com")
    }

    @Test
    func pathPrefixOverride_replacesMatchedPrefixAndKeepsRemainder() async throws {
        // Given / When
        let resolved = try await resolve(
            TestProperty {
                BaseURL("google.com")
                Path("api/v1")
                Path("users")
                URLOverride("https://apple.com/v2", from: "https://google.com/api/v1")
            }
        )

        // Then
        #expect(resolved.requestConfiguration.url == "https://apple.com/v2/users")
    }

    @Test
    func pathPrefixOverride_keepsQueryUntouched() async throws {
        // Given / When
        let resolved = try await resolve(
            TestProperty {
                BaseURL("google.com")
                Path("api/v1")
                Query(name: "id", value: 42)
                URLOverride("https://apple.com/v2", from: "https://google.com/api/v1")
            }
        )

        // Then
        #expect(resolved.requestConfiguration.url == "https://apple.com/v2?id=42")
    }

    @Test
    func pathPrefixOverride_matchesByComponentNotRawString() async throws {
        // Given / When: "api/v10" must not be treated as prefixed by "api/v1".
        let resolved = try await resolve(
            TestProperty {
                BaseURL("google.com")
                Path("api/v10")
                URLOverride("https://apple.com/v2", from: "https://google.com/api/v1")
            }
        )

        // Then
        #expect(resolved.requestConfiguration.url == "https://google.com/api/v10")
    }

    @Test
    func override_appliesAgainstFinalBaseURL_regardlessOfDeclarationOrder() async throws {
        // Given / When: `URLOverride` declared before the `BaseURL` that ends up winning.
        let resolved = try await resolve(
            TestProperty {
                URLOverride("https://apple.com", from: "https://google.com")
                BaseURL(.ftp, host: "unrelated.com")
                BaseURL("google.com")
            }
        )

        // Then
        #expect(resolved.requestConfiguration.url == "https://apple.com")
    }

    @Test
    func unmatchedOrigin_leavesRequestUnchanged() async throws {
        // Given / When
        let resolved = try await resolve(
            TestProperty {
                BaseURL("example.com")
                URLOverride("https://apple.com", from: "https://google.com")
            }
        )

        // Then
        #expect(resolved.requestConfiguration.url == "https://example.com")
    }

    @Test
    func lastDeclaredRuleWinsForSameOrigin() async throws {
        // Given / When
        let resolved = try await resolve(
            TestProperty {
                BaseURL("google.com")
                URLOverride("https://first.com", from: "https://google.com")
                URLOverride("https://second.com", from: "https://google.com")
            }
        )

        // Then
        #expect(resolved.requestConfiguration.url == "https://second.com")
    }

    /// The documented dictionary example declares a whole-host rule and a path-scoped rule for
    /// the same host. `Dictionary` iteration order varies between launches, and "last matching
    /// rule wins" then picked a different destination from one launch to the next. The most
    /// specific (longest) matching origin path now wins, whatever the declaration order.
    @Test(arguments: [false, true])
    func mostSpecificOriginPathWinsRegardlessOfDeclarationOrder(pathScopedFirst: Bool) async throws {
        // Given / When
        let resolved = try await resolve(
            TestProperty {
                BaseURL("google.com")
                Path("api/v1/users")

                if pathScopedFirst {
                    URLOverride("https://apple.com/v2", from: "https://google.com/api/v1")
                    URLOverride("https://apple.com", from: "https://google.com")
                } else {
                    URLOverride("https://apple.com", from: "https://google.com")
                    URLOverride("https://apple.com/v2", from: "https://google.com/api/v1")
                }
            }
        )

        // Then
        #expect(resolved.requestConfiguration.url == "https://apple.com/v2/users")
    }

    @Test
    func dictionaryWithOverlappingOriginsResolvesToTheMostSpecificRule() async throws {
        // Given / When
        let resolved = try await resolve(
            TestProperty {
                BaseURL("google.com")
                Path("api/v1/users")
                URLOverride([
                    "https://google.com": "https://apple.com",
                    "https://google.com/api/v1": "https://apple.com/v2",
                ])
            }
        )

        // Then
        #expect(resolved.requestConfiguration.url == "https://apple.com/v2/users")
    }

    @Test
    func destinationIsNeverRematchedAgainstOtherRules() async throws {
        // Given / When: a.com -> b.com is declared, and b.com -> c.com is declared, but a
        // resolved request should stop at b.com rather than chaining through to c.com.
        let resolved = try await resolve(
            TestProperty {
                BaseURL("a.com")
                URLOverride("https://b.com", from: "https://a.com")
                URLOverride("https://c.com", from: "https://b.com")
            }
        )

        // Then
        #expect(resolved.requestConfiguration.url == "https://b.com")
    }

    @Test
    func dictionaryInitializer_appliesMatchingEntry() async throws {
        // Given / When: non-overlapping origins, so the dictionary's unspecified iteration
        // order can't make the match ambiguous (overlapping scopes are documented as undefined).
        let resolved = try await resolve(
            TestProperty {
                BaseURL("google.com")
                Path("api/v1")
                URLOverride([
                    "https://google.com/api/v1": "https://apple.com/v2",
                    "https://example.com": "https://unused.com",
                ])
            }
        )

        // Then
        #expect(resolved.requestConfiguration.url == "https://apple.com/v2")
    }

    // MARK: - What counts as the same origin

    /// Scheme and host are compared case-insensitively and a port left out is the scheme's
    /// default, so the same origin spelled another way still matches its rule.
    @Test
    func origin_matchesWhateverTheCaseOfSchemeAndHost() async throws {
        let ruleInUpperCase = try await resolve(
            TestProperty {
                BaseURL("google.com")
                URLOverride("https://apple.com", from: "HTTPS://Google.COM")
            }
        )

        let requestInUpperCase = try await resolve(
            TestProperty {
                BaseURL("Google.COM")
                URLOverride("https://apple.com", from: "https://google.com")
            }
        )

        #expect(ruleInUpperCase.requestConfiguration.url == "https://apple.com")
        #expect(requestInUpperCase.requestConfiguration.url == "https://apple.com")
    }

    @Test
    func origin_whenTheRequestNamesTheDefaultPort_matchesARuleThatDoesNot() async throws {
        let https = try await resolve(
            TestProperty {
                BaseURL(.https, host: "google.com:443")
                URLOverride("https://apple.com", from: "https://google.com")
            }
        )

        let http = try await resolve(
            TestProperty {
                BaseURL(.http, host: "google.com:80")
                URLOverride("http://apple.com", from: "http://google.com")
            }
        )

        #expect(https.requestConfiguration.url == "https://apple.com")
        #expect(http.requestConfiguration.url == "http://apple.com")
    }

    @Test
    func origin_whenTheRuleNamesTheDefaultPort_matchesARequestThatDoesNot() async throws {
        let resolved = try await resolve(
            TestProperty {
                BaseURL("google.com")
                URLOverride("https://apple.com", from: "https://google.com:443")
            }
        )

        #expect(resolved.requestConfiguration.url == "https://apple.com")
    }

    /// A port that is not the scheme's default is a different origin, as before.
    @Test
    func origin_whenThePortIsNotTheDefault_stillDiffers() async throws {
        let requestOnAnotherPort = try await resolve(
            TestProperty {
                BaseURL(.https, host: "google.com:8443")
                URLOverride("https://apple.com", from: "https://google.com")
            }
        )

        let ruleOnAnotherPort = try await resolve(
            TestProperty {
                BaseURL("google.com")
                URLOverride("https://apple.com", from: "https://google.com:8443")
            }
        )

        let otherSchemeDefault = try await resolve(
            TestProperty {
                BaseURL(.http, host: "google.com:443")
                URLOverride("https://apple.com", from: "http://google.com")
            }
        )

        #expect(requestOnAnotherPort.requestConfiguration.url == "https://google.com:8443")
        #expect(ruleOnAnotherPort.requestConfiguration.url == "https://google.com")
        #expect(otherSchemeDefault.requestConfiguration.url == "http://google.com:443")
    }

    @Test
    func originScheme_mustMatch() async throws {
        // Given / When
        let resolved = try await resolve(
            TestProperty {
                BaseURL(.http, host: "google.com")
                URLOverride("https://apple.com", from: "https://google.com")
            }
        )

        // Then
        #expect(resolved.requestConfiguration.url == "http://google.com")
    }

    @Test
    func origin_whenMissingScheme_throws() async throws {
        // Given
        let origin = "google.com"

        do {
            // When
            _ = try await resolve(
                TestProperty {
                    BaseURL("google.com")
                    URLOverride("https://apple.com", from: origin)
                }
            )

            // Then
            Issue.record("Not expecting success")
        } catch let error as URLOverrideError {
            #expect(error.context == .missingScheme)
            #expect(error.url == origin)
        } catch {
            throw error
        }
    }

    @Test
    func destination_whenMissingScheme_throws() async throws {
        // Given
        let destination = "apple.com"

        do {
            // When
            _ = try await resolve(
                TestProperty {
                    BaseURL("google.com")
                    URLOverride(destination, from: "https://google.com")
                }
            )

            // Then
            Issue.record("Not expecting success")
        } catch let error as URLOverrideError {
            #expect(error.context == .missingScheme)
            #expect(error.url == destination)
        } catch {
            throw error
        }
    }

    @Test
    func origin_whenMissingHost_throws() async throws {
        // Given
        let origin = "https://"

        do {
            // When
            _ = try await resolve(
                TestProperty {
                    BaseURL("google.com")
                    URLOverride("https://apple.com", from: origin)
                }
            )

            // Then
            Issue.record("Not expecting success")
        } catch let error as URLOverrideError {
            #expect(error.context == .missingHost)
            #expect(error.url == origin)
        } catch {
            throw error
        }
    }

    @Test
    func origin_whenEmptyString_throws() async throws {
        // Given
        let origin = ""

        do {
            // When
            _ = try await resolve(
                TestProperty {
                    BaseURL("google.com")
                    URLOverride("https://apple.com", from: origin)
                }
            )

            // Then
            Issue.record("Not expecting success")
        } catch let error as URLOverrideError {
            #expect(error.context == .invalidURL)
            #expect(error.url == origin)
        } catch {
            throw error
        }
    }

    @Test
    func neverBody() async throws {
        // Given
        let property = URLOverride("https://apple.com", from: "https://google.com")

        // Then
        try await assertNever(property.body)
    }
}
