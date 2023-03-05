//
//  PropertyBuilderTests.swift
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

final class PropertyBuilderTests: XCTestCase {

    func testSingleBuildBlock() async throws {
        // Given
        @PropertyBuilder
        var property: some Property {
            Headers.ContentType(.json)
        }

        // When
        let (_, request) = await resolve(TestProperty(property))

        // Then
        XCTAssertTrue(property is Headers.ContentType)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func testLimitedNotAvailableBuildBlock() async throws {
        // Given
        @PropertyBuilder
        var property: some Property {
            if #available(iOS 99, macOS 99, watchOS 99, tvOS 99, *) {
                Headers.ContentType(.json)
            }
        }

        // When
        let (_, request) = await resolve(TestProperty(property))

        // Then
        print(type(of: property))
        XCTAssertTrue(property is _OptionalContent<Headers.ContentType>)
        XCTAssertNil(request.allHTTPHeaderFields)
    }

    func testLimitedAvailableBuildBlock() async throws {
        // Given
        @PropertyBuilder
        var property: some Property {
            if #available(iOS 14, macOS 12, watchOS 7, tvOS 14, *) {
                Headers.ContentType(.json)
            }
        }

        // When
        let (_, request) = await resolve(TestProperty(property))

        // Then
        print(type(of: property))
        XCTAssertTrue(property is _OptionalContent<Headers.ContentType>)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }
}
