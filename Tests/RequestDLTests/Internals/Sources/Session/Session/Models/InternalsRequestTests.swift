/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
import NIOCore
@testable import RequestDL

struct InternalsRequestTests {

    @Test
    func request_whenInitURL_shouldBeEqual() async throws {
        // Given
        var request = Internals.Request()
        let url = "https://google.com"

        // When
        request.baseURL = url

        // Then
        #expect(request.url == url)
    }

    @Test
    func request_whenMethodIsAssign_shouldBeEqual() async throws {
        // Given
        var request = Internals.Request()
        let method = "POST"

        // When
        request.method = method

        // Then
        #expect(request.method == method)
    }

    @Test
    func request_whenHeadersAreSet_shouldContainsValues() async throws {
        // Given
        var request = Internals.Request()

        let key1 = "Content-Type"
        let value1 = "application/json"

        let key2 = "Accept"
        let value2 = "text/html"

        // When
        request.headers.set(name: key1, value: value1)
        request.headers.set(name: key2, value: value2)

        // Then
        #expect(request.headers.count == 2)
        #expect(request.headers[key1] == [value1])
        #expect(request.headers[key2] == [value2])
    }

    @Test
    func request_whenSetReadingMode() async throws {
        // Given
        var request = Internals.Request()
        let readingMode = Internals.DownloadStep.ReadingMode.separator([70])

        // When
        request.readingMode = readingMode

        // Then
        #expect(request.readingMode == readingMode)
    }

    @Test
    func request_whenUnsetReadingMode() async throws {
        // Given
        let request = Internals.Request()
        // Then
        #expect(request.readingMode == .length(1_024))
    }
}
