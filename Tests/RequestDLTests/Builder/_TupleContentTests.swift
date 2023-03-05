//
//  _TupleContentTests.swift
//
//  MIT License
//
//  Copyright (c) RequestDL
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

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
}
