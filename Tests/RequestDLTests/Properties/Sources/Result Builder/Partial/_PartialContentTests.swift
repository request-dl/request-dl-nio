/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct _PartialContentTests {

    @Test
    func tupleTwoElementsBuilder() async throws {
        // Given
        @PropertyBuilder
        var result: some Property {
            BaseURL("google.com")
            OriginHeader("https://apple.com")
        }

        // When
        let resolved = try await resolve(result)

        // Then
        #expect(result is _PartialContent<
            BaseURL,
            OriginHeader
        >)

        #expect(resolved.request.url == "https://google.com")
        #expect(resolved.request.headers["Origin"] == ["https://apple.com"])
    }

    @Test
    func tupleThreeElementsBuilder() async throws {
        // Given
        @PropertyBuilder
        var result: some Property {
            BaseURL("google.com")
            OriginHeader("https://apple.com")
            CacheHeader()
                .public(true)
        }

        // When
        let resolved = try await resolve(result)

        // Then
        #expect(result is _PartialContent<
            _PartialContent<
                BaseURL,
                OriginHeader
            >,
            CacheHeader
        >)

        #expect(resolved.request.url == "https://google.com")
        #expect(resolved.request.headers["Origin"] == ["https://apple.com"])
        #expect(resolved.request.headers["Cache-Control"] == ["public"])
    }

    @Test
    func tupleFourElementsBuilder() async throws {
        // Given
        @PropertyBuilder
        var result: some Property {
            BaseURL("google.com")
            OriginHeader("https://apple.com")
            CacheHeader()
                .public(true)
            Path("search")
        }

        // When
        let resolved = try await resolve(result)

        // Then
        #expect(result is _PartialContent<
            _PartialContent<
                _PartialContent<
                    BaseURL,
                    OriginHeader
                >,
                CacheHeader
            >,
            Path
        >)

        #expect(resolved.request.url == "https://google.com/search")
        #expect(resolved.request.headers["Origin"] == ["https://apple.com"])
        #expect(resolved.request.headers["Cache-Control"] == ["public"])
    }

    @Test
    func tupleFiveElementsBuilder() async throws {
        // Given
        @PropertyBuilder
        var result: some Property {
            BaseURL("google.com")
            OriginHeader("https://apple.com")
            CacheHeader()
                .public(true)
            Path("search")
            Query(name: "q", value: "request-dl")
        }

        // When
        let resolved = try await resolve(result)

        // Then
        #expect(result is _PartialContent<
            _PartialContent<
                _PartialContent<
                    _PartialContent<
                        BaseURL,
                        OriginHeader
                    >,
                    CacheHeader
                >,
                Path
            >,
            Query<String>
        >)

        #expect(
            resolved.request.url == "https://google.com/search?q=request-dl"
        )

        #expect(resolved.request.headers["Origin"] == ["https://apple.com"])
        #expect(resolved.request.headers["Cache-Control"] == ["public"])
    }

    @Test
    func tupleSixElementsBuilder() async throws {
        // Given
        @PropertyBuilder
        var result: some Property {
            BaseURL("google.com")
            OriginHeader("https://apple.com")
            CacheHeader()
                .public(true)
            Path("search")
            Query(name: "q", value: "request-dl")
            Timeout(40)
        }

        // When
        let resolved = try await resolve(result)

        // Then
        #expect(result is _PartialContent<
            _PartialContent<
                _PartialContent<
                    _PartialContent<
                        _PartialContent<
                            BaseURL,
                            OriginHeader
                        >,
                        CacheHeader
                    >,
                    Path
                >,
                Query<String>
            >,
            Timeout
        >)

        #expect(
            resolved.request.url == "https://google.com/search?q=request-dl"
        )

        #expect(resolved.request.headers["Origin"] == ["https://apple.com"])
        #expect(resolved.request.headers["Cache-Control"] == ["public"])

        #expect(resolved.session.configuration.timeout.read == .nanoseconds(40))
        #expect(resolved.session.configuration.timeout.connect == .nanoseconds(40))
    }

    @Test
    func tupleSevenElementsBuilder() async throws {
        // Given
        @PropertyBuilder
        var result: some Property {
            BaseURL("google.com")
            OriginHeader("https://apple.com")
            CacheHeader()
                .public(true)
            Path("search")
            Query(name: "q", value: "request-dl")
            Timeout(40)
            Query(name: "page", value: 1)
        }

        // When
        let resolved = try await resolve(result)

        // Then
        #expect(result is _PartialContent<
            _PartialContent<
                _PartialContent<
                    _PartialContent<
                        _PartialContent<
                            _PartialContent<
                                BaseURL,
                                OriginHeader
                            >,
                            CacheHeader
                        >,
                        Path
                    >,
                    Query<String>
                >,
                Timeout
            >,
            Query<Int>
        >)

        #expect(
            resolved.request.url == "https://google.com/search?q=request-dl&page=1"
        )

        #expect(resolved.request.headers["Origin"] == ["https://apple.com"])
        #expect(resolved.request.headers["Cache-Control"] == ["public"])

        #expect(resolved.session.configuration.timeout.read == .nanoseconds(40))
        #expect(resolved.session.configuration.timeout.connect == .nanoseconds(40))
    }

    @Test
    func tupleEightElementsBuilder() async throws {
        // Given
        @PropertyBuilder
        var result: some Property {
            BaseURL("google.com")
            OriginHeader("https://apple.com")
            CacheHeader()
                .public(true)
            Path("search")
            Query(name: "q", value: "request-dl")
            Timeout(40)
            Query(name: "page", value: 1)
            Path("results")
        }

        // When
        let resolved = try await resolve(result)

        // Then
        #expect(result is _PartialContent<
            _PartialContent<
                _PartialContent<
                    _PartialContent<
                        _PartialContent<
                            _PartialContent<
                                _PartialContent<
                                    BaseURL,
                                    OriginHeader
                                >,
                                CacheHeader
                            >,
                            Path
                        >,
                        Query<String>
                    >,
                    Timeout
                >,
                Query<Int>
            >,
            Path
        >)

        #expect(
            resolved.request.url == "https://google.com/search/results?q=request-dl&page=1"
        )

        #expect(resolved.request.headers["Origin"] == ["https://apple.com"])
        #expect(resolved.request.headers["Cache-Control"] == ["public"])

        #expect(resolved.session.configuration.timeout.read == .nanoseconds(40))
        #expect(resolved.session.configuration.timeout.connect == .nanoseconds(40))
    }

    @Test
    func neverBody() async throws {
        // Given
        let property = _PartialContent<EmptyProperty, EmptyProperty>(
            accumulated: .init(),
            next: .init()
        )

        // Then
        try await assertNever(property.body)
    }
}
