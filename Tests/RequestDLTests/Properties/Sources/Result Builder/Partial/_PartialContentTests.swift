/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class _PartialContentTests: XCTestCase {

    func testTupleTwoElementsBuilder() async throws {
        // Given
        @PropertyBuilder
        var result: some Property {
            BaseURL("google.com")
            Headers.Origin("https://apple.com")
        }

        // When
        let resolved = try await resolve(result)

        // Then
        XCTAssertTrue(result is _PartialContent<
            BaseURL,
            Headers.Origin
        >)

        XCTAssertEqual(resolved.request.url, "https://google.com")
        XCTAssertEqual(resolved.request.headers["Origin"], ["https://apple.com"])
    }

    func testTupleThreeElementsBuilder() async throws {
        // Given
        @PropertyBuilder
        var result: some Property {
            BaseURL("google.com")
            Headers.Origin("https://apple.com")
            Headers.Cache()
                .public(true)
        }

        // When
        let resolved = try await resolve(result)

        // Then
        XCTAssertTrue(result is _PartialContent<
            _PartialContent<
                BaseURL,
                Headers.Origin
            >,
            Headers.Cache
        >)

        XCTAssertEqual(resolved.request.url, "https://google.com")
        XCTAssertEqual(resolved.request.headers["Origin"], ["https://apple.com"])
        XCTAssertEqual(resolved.request.headers["Cache-Control"], ["public"])
    }

    func testTupleFourElementsBuilder() async throws {
        // Given
        @PropertyBuilder
        var result: some Property {
            BaseURL("google.com")
            Headers.Origin("https://apple.com")
            Headers.Cache()
                .public(true)
            Path("search")
        }

        // When
        let resolved = try await resolve(result)

        // Then
        XCTAssertTrue(result is _PartialContent<
            _PartialContent<
                _PartialContent<
                    BaseURL,
                    Headers.Origin
                >,
                Headers.Cache
            >,
            Path
        >)

        XCTAssertEqual(resolved.request.url, "https://google.com/search")
        XCTAssertEqual(resolved.request.headers["Origin"], ["https://apple.com"])
        XCTAssertEqual(resolved.request.headers["Cache-Control"], ["public"])
    }

    func testTupleFiveElementsBuilder() async throws {
        // Given
        @PropertyBuilder
        var result: some Property {
            BaseURL("google.com")
            Headers.Origin("https://apple.com")
            Headers.Cache()
                .public(true)
            Path("search")
            Query("request-dl", forKey: "q")
        }

        // When
        let resolved = try await resolve(result)

        // Then
        XCTAssertTrue(result is _PartialContent<
            _PartialContent<
                _PartialContent<
                    _PartialContent<
                        BaseURL,
                        Headers.Origin
                    >,
                    Headers.Cache
                >,
                Path
            >,
            Query<String>
        >)

        XCTAssertEqual(
            resolved.request.url,
            "https://google.com/search?q=request-dl"
        )

        XCTAssertEqual(resolved.request.headers["Origin"], ["https://apple.com"])
        XCTAssertEqual(resolved.request.headers["Cache-Control"], ["public"])
    }

    func testTupleSixElementsBuilder() async throws {
        // Given
        @PropertyBuilder
        var result: some Property {
            BaseURL("google.com")
            Headers.Origin("https://apple.com")
            Headers.Cache()
                .public(true)
            Path("search")
            Query("request-dl", forKey: "q")
            Timeout(40)
        }

        // When
        let resolved = try await resolve(result)

        // Then
        XCTAssertTrue(result is _PartialContent<
            _PartialContent<
                _PartialContent<
                    _PartialContent<
                        _PartialContent<
                            BaseURL,
                            Headers.Origin
                        >,
                        Headers.Cache
                    >,
                    Path
                >,
                Query<String>
            >,
            Timeout
        >)

        XCTAssertEqual(
            resolved.request.url,
            "https://google.com/search?q=request-dl"
        )

        XCTAssertEqual(resolved.request.headers["Origin"], ["https://apple.com"])
        XCTAssertEqual(resolved.request.headers["Cache-Control"], ["public"])

        XCTAssertEqual(resolved.session.configuration.timeout.read, .nanoseconds(40))
        XCTAssertEqual(resolved.session.configuration.timeout.connect, .nanoseconds(40))
    }

    func testTupleSevenElementsBuilder() async throws {
        // Given
        @PropertyBuilder
        var result: some Property {
            BaseURL("google.com")
            Headers.Origin("https://apple.com")
            Headers.Cache()
                .public(true)
            Path("search")
            Query("request-dl", forKey: "q")
            Timeout(40)
            Query(1, forKey: "page")
        }

        // When
        let resolved = try await resolve(result)

        // Then
        XCTAssertTrue(result is _PartialContent<
            _PartialContent<
                _PartialContent<
                    _PartialContent<
                        _PartialContent<
                            _PartialContent<
                                BaseURL,
                                Headers.Origin
                            >,
                            Headers.Cache
                        >,
                        Path
                    >,
                    Query<String>
                >,
                Timeout
            >,
            Query<Int>
        >)

        XCTAssertEqual(
            resolved.request.url,
            "https://google.com/search?q=request-dl&page=1"
        )

        XCTAssertEqual(resolved.request.headers["Origin"], ["https://apple.com"])
        XCTAssertEqual(resolved.request.headers["Cache-Control"], ["public"])

        XCTAssertEqual(resolved.session.configuration.timeout.read, .nanoseconds(40))
        XCTAssertEqual(resolved.session.configuration.timeout.connect, .nanoseconds(40))
    }

    func testTupleEightElementsBuilder() async throws {
        // Given
        @PropertyBuilder
        var result: some Property {
            BaseURL("google.com")
            Headers.Origin("https://apple.com")
            Headers.Cache()
                .public(true)
            Path("search")
            Query("request-dl", forKey: "q")
            Timeout(40)
            Query(1, forKey: "page")
            Path("results")
        }

        // When
        let resolved = try await resolve(result)

        // Then
        XCTAssertTrue(result is _PartialContent<
            _PartialContent<
                _PartialContent<
                    _PartialContent<
                        _PartialContent<
                            _PartialContent<
                                _PartialContent<
                                    BaseURL,
                                    Headers.Origin
                                >,
                                Headers.Cache
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

        XCTAssertEqual(
            resolved.request.url,
            "https://google.com/search/results?q=request-dl&page=1"
        )

        XCTAssertEqual(resolved.request.headers["Origin"], ["https://apple.com"])
        XCTAssertEqual(resolved.request.headers["Cache-Control"], ["public"])

        XCTAssertEqual(resolved.session.configuration.timeout.read, .nanoseconds(40))
        XCTAssertEqual(resolved.session.configuration.timeout.connect, .nanoseconds(40))
    }

    func testNeverBody() async throws {
        // Given
        let property = _PartialContent<EmptyProperty, EmptyProperty>(
            accumulated: .init(),
            next: .init()
        )

        // Then
        try await assertNever(property.body)
    }
}
