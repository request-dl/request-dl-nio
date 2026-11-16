//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL
@testable import RequestDLInternals

struct RequestConfigurationTests {

    @Test
    func request_whenInitURL_shouldBeEqual() async throws {
        // Given
        var request = RequestConfiguration()
        let url = "https://google.com"

        // When
        request.baseURL = url

        // Then
        #expect(request.url == url)
    }

    @Test
    func request_whenBuiltFromBaseAndPath_stillTrimsTheSlashesAroundThem() async throws {
        // Given
        var request = RequestConfiguration()

        // When
        request.baseURL = " https://example.com/ "
        request.pathComponents = ["/files/", "abc/"]

        // Then: what an upload that keeps the exact URL of a server relies on is not what any other
        // request gets.
        #expect(request.url == "https://example.com/files/abc/")

        request.pathComponents = []
        #expect(request.url == "https://example.com")
    }

    @Test
    func request_whenGivenAnExactURL_isThatURLToTheLastCharacter() async throws {
        // Given
        var request = RequestConfiguration()
        request.baseURL = "https://example.com"
        request.pathComponents = ["other"]
        request.queries = [QueryItem(name: "a", value: "b")]

        // When
        request.exactURL = "https://example.com/files/abc/"

        // Then
        #expect(request.url == "https://example.com/files/abc/")
    }

    @Test
    func request_whenMethodIsAssign_shouldBeEqual() async throws {
        // Given
        var request = RequestConfiguration()
        let method = "POST"

        // When
        request.method = method

        // Then
        #expect(request.method == method)
    }

    @Test
    func request_whenHeadersAreSet_shouldContainsValues() async throws {
        // Given
        var request = RequestConfiguration()

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
        var request = RequestConfiguration()
        let readingMode = Internals.DownloadStep.ReadingMode.separator([70])

        // When
        request.readingMode = readingMode

        // Then
        #expect(request.readingMode == readingMode)
    }

    @Test
    func request_whenUnsetReadingMode() async throws {
        // Given
        let request = RequestConfiguration()
        // Then
        #expect(request.readingMode == .length(1_024))
    }
}
