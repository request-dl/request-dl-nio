/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

final class _TupleContentTests: XCTestCase {

    func testTupleTwoElementsBuilder() async {
        // Given
        @PropertyBuilder
        var result: some Property {
            BaseURL("google.com")
            Headers.Origin("https://apple.com")
        }

        // When
        let (_, request) = await resolve(result)

        // Then
        XCTAssertTrue(result is _TupleContent<(
            BaseURL,
            Headers.Origin
        )>)

        XCTAssertEqual(request.url?.absoluteString, "https://google.com")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Origin"), "https://apple.com")
    }

    func testTupleThreeElementsBuilder() async {
        // Given
        @PropertyBuilder
        var result: some Property {
            BaseURL("google.com")
            Headers.Origin("https://apple.com")
            Headers.ContentType(.json)
        }

        // When
        let (_, request) = await resolve(result)

        // Then
        XCTAssertTrue(result is _TupleContent<(
            BaseURL,
            Headers.Origin,
            Headers.ContentType
        )>)

        XCTAssertEqual(request.url?.absoluteString, "https://google.com")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Origin"), "https://apple.com")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func testTupleFourElementsBuilder() async {
        // Given
        @PropertyBuilder
        var result: some Property {
            BaseURL("google.com")
            Headers.Origin("https://apple.com")
            Headers.ContentType(.json)
            Path("search")
        }

        // When
        let (_, request) = await resolve(result)

        // Then
        XCTAssertTrue(result is _TupleContent<(
            BaseURL,
            Headers.Origin,
            Headers.ContentType,
            Path
        )>)

        XCTAssertEqual(request.url?.absoluteString, "https://google.com/search")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Origin"), "https://apple.com")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func testTupleFiveElementsBuilder() async {
        // Given
        @PropertyBuilder
        var result: some Property {
            BaseURL("google.com")
            Headers.Origin("https://apple.com")
            Headers.ContentType(.json)
            Path("search")
            Query("request-dl", forKey: "q")
        }

        // When
        let (_, request) = await resolve(result)

        // Then
        XCTAssertTrue(result is _TupleContent<(
            BaseURL,
            Headers.Origin,
            Headers.ContentType,
            Path,
            Query
        )>)

        XCTAssertEqual(
            request.url?.absoluteString,
            "https://google.com/search?q=request-dl"
        )

        XCTAssertEqual(request.value(forHTTPHeaderField: "Origin"), "https://apple.com")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func testTupleSixElementsBuilder() async {
        // Given
        @PropertyBuilder
        var result: some Property {
            BaseURL("google.com")
            Headers.Origin("https://apple.com")
            Headers.ContentType(.json)
            Path("search")
            Query("request-dl", forKey: "q")
            Timeout(40)
        }

        // When
        let (session, request) = await resolve(result)

        // Then
        XCTAssertTrue(result is _TupleContent<(
            BaseURL,
            Headers.Origin,
            Headers.ContentType,
            Path,
            Query,
            Timeout
        )>)

        XCTAssertEqual(
            request.url?.absoluteString,
            "https://google.com/search?q=request-dl"
        )

        XCTAssertEqual(request.value(forHTTPHeaderField: "Origin"), "https://apple.com")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        XCTAssertEqual(session.configuration.timeoutIntervalForResource, 40)
        XCTAssertEqual(session.configuration.timeoutIntervalForRequest, 40)
    }

    func testTupleSevenElementsBuilder() async {
        // Given
        @PropertyBuilder
        var result: some Property {
            BaseURL("google.com")
            Headers.Origin("https://apple.com")
            Headers.ContentType(.json)
            Path("search")
            Query("request-dl", forKey: "q")
            Timeout(40)
            Query(1, forKey: "page")
        }

        // When
        let (session, request) = await resolve(result)

        // Then
        XCTAssertTrue(result is _TupleContent<(
            BaseURL,
            Headers.Origin,
            Headers.ContentType,
            Path,
            Query,
            Timeout,
            Query
        )>)

        XCTAssertEqual(
            request.url?.absoluteString,
            "https://google.com/search?q=request-dl&page=1"
        )

        XCTAssertEqual(request.value(forHTTPHeaderField: "Origin"), "https://apple.com")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        XCTAssertEqual(session.configuration.timeoutIntervalForResource, 40)
        XCTAssertEqual(session.configuration.timeoutIntervalForRequest, 40)
    }

    func testTupleEightElementsBuilder() async {
        // Given
        @PropertyBuilder
        var result: some Property {
            BaseURL("google.com")
            Headers.Origin("https://apple.com")
            Headers.ContentType(.json)
            Path("search")
            Query("request-dl", forKey: "q")
            Timeout(40)
            Query(1, forKey: "page")
            Path("results")
        }

        // When
        let (session, request) = await resolve(result)

        // Then
        XCTAssertTrue(result is _TupleContent<(
            BaseURL,
            Headers.Origin,
            Headers.ContentType,
            Path,
            Query,
            Timeout,
            Query,
            Path
        )>)

        XCTAssertEqual(
            request.url?.absoluteString,
            "https://google.com/search/results?q=request-dl&page=1"
        )

        XCTAssertEqual(request.value(forHTTPHeaderField: "Origin"), "https://apple.com")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        XCTAssertEqual(session.configuration.timeoutIntervalForResource, 40)
        XCTAssertEqual(session.configuration.timeoutIntervalForRequest, 40)
    }

    func testNeverBody() async throws {
        // Given
        let property = _TupleContent<EmptyProperty>(transform: { _ in })

        // Then
        try await assertNever(property.body)
    }
}