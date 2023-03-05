//
//  PathTests.swift
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

final class PathTests: XCTestCase {

    func testSinglePath() async {
        // Given
        let path = "api"
        let host = "google.com"

        // When
        let (_, request) = await resolve(TestProperty {
            BaseURL(host)
            Path(path)
        })

        // Then
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://\(host)/\(path)"
        )
    }

    func testSingleInstanceWithMultiplePath() async {
        // Given
        let path = "api/v1/users/10/detail"
        let host = "google.com"

        // When
        let (_, request) = await resolve(TestProperty {
            BaseURL(host)
            Path(path)
        })

        // Then
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://\(host)/\(path)"
        )
    }

    func testMultiplePath() async {
        // Given
        let path1 = "api"
        let path2 = "v1/"
        let path3 = "/users/10/detail"
        let host = "google.com"
        let characterSetRule = CharacterSet(charactersIn: "/")

        // When
        let (_, request) = await resolve(TestProperty {
            BaseURL(host)
            Path(path1)
            Path(path2)
            Path(path3)
        })

        // Then
        let expectedPath2 = path2.trimmingCharacters(in: characterSetRule)
        let expectedPath3 = path3.trimmingCharacters(in: characterSetRule)

        XCTAssertEqual(
            request.url?.absoluteString,
            "https://\(host)/\(path1)/\(expectedPath2)/\(expectedPath3)"
        )
    }
}
