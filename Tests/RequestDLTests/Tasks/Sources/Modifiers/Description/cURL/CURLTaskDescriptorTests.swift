//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

/// No `LocalServer` anywhere here -- `.description(_:)` only resolves the `Property` graph
/// (`Resolve(...).partiallyBuild()`), it never builds a session or touches the network.
struct CURLTaskDescriptorTests {

    @Test
    func plainGETHasNoExplicitMethodFlag() async throws {
        // Given / When
        let command = try await DataTask {
            BaseURL("example.com")
            Path("users")
        }
        .description(.cURL)

        // Then
        #expect(command.contains("curl"))
        #expect(command.contains("'https://example.com/users'"))
        #expect(!command.contains("-X"))
    }

    @Test
    func explicitMethodAndHeaders() async throws {
        // Given / When
        let command = try await DataTask {
            BaseURL("example.com")
            RequestMethod(.post)
            CustomHeader(name: "Accept", value: "application/json")
        }
        .description(.cURL)

        // Then
        #expect(command.contains("-X POST"))
        #expect(command.contains("-H 'Accept: application/json'"))
    }

    @Test
    func queryIsPartOfTheURL() async throws {
        // Given / When
        let command = try await DataTask {
            BaseURL("example.com")
            Path("search")
            Query(name: "q", value: "swift")
        }
        .description(.cURL)

        // Then
        #expect(command.contains("q=swift"))
    }

    @Test
    func plainPayloadBecomesDataRaw() async throws {
        // Given / When
        let command = try await DataTask {
            BaseURL("example.com")
            Payload(verbatim: "hello world", contentType: .text)
        }
        .description(.cURL)

        // Then
        #expect(command.contains("--data-raw 'hello world'"))
        #expect(command.contains("-H 'Content-Type: text/plain; charset=UTF-8'"))
        // curl computes this itself.
        #expect(!command.contains("Content-Length"))
    }

    @Test
    func multipartFormBecomesOneFlagPerField() async throws {
        // Given / When
        let command = try await DataTask {
            BaseURL("example.com")
            Form(name: "name", verbatim: "John Doe")
            Form(name: "avatar", filename: "avatar.png", contentType: .png, data: Data("bytes".utf8))
        }
        .description(.cURL)

        // Then -- one `-F` per field, not a flattened blob.
        #expect(command.contains(#"-F 'name=John Doe'"#))
        #expect(command.contains("-F 'avatar=@avatar.png;type=image/png'"))

        // The multipart body's own `Content-Type` (with its now-irrelevant boundary) must not
        // leak into a generic `-H`, since curl derives its own from `-F`.
        #expect(!command.contains("multipart/form-data"))
    }

    /// A plain (no `filename`) form field's bytes aren't necessarily valid UTF-8 -- e.g. binary
    /// `Data` handed to `Form` without a filename. Regression test for a bug where those bytes
    /// were lossily decoded to `String` (replacing anything invalid with U+FFFD) before ever
    /// reaching `curlShellQuote`'s own byte-safe fallback, silently corrupting the value.
    @Test
    func binaryFormFieldContentIsNotCorrupted() async throws {
        // Given
        let binary = Data([0xFF, 0xFE, 0x00, 0x01])

        // When
        let command = try await DataTask {
            BaseURL("example.com")
            Form(name: "blob", contentType: .octetStream, data: binary)
        }
        .description(.cURL)

        // Then
        #expect(command.contains(#"\xff\xfe\x00\x01"#))
        #expect(!command.contains("\u{FFFD}"))
    }

    @Test
    func basicAuthorizationBecomesUserFlag() async throws {
        // Given / When
        let command = try await DataTask {
            BaseURL("example.com")
            Authorization(username: "john", password: "secret")
        }
        .description(.cURL)

        // Then
        #expect(command.contains("-u 'john:secret'"))
        #expect(!command.contains("-H 'Authorization"))
    }

    @Test
    func bearerAuthorizationStaysAsAHeader() async throws {
        // Given / When
        let command = try await DataTask {
            BaseURL("example.com")
            Authorization(.bearer, token: "abc123")
        }
        .description(.cURL)

        // Then
        #expect(command.contains("-H 'Authorization: Bearer abc123'"))
        #expect(!command.contains("-u "))
    }

    @Test
    func roundTripsThroughCURLCommandParser() async throws {
        // Given
        let command = try await DataTask {
            BaseURL("example.com")
            Path("users")
            RequestMethod(.post)
            CustomHeader(name: "Accept", value: "application/json")
            Payload(verbatim: "hello", contentType: .text)
        }
        .description(.cURL)

        // When
        let configuration = try await CURLCommandParser.parse(command)

        // Then
        #expect(configuration.url == "https://example.com/users")
        #expect(configuration.method == "POST")
        #expect(configuration.headers["Accept"] == ["application/json"])
    }

    @Test
    func availableOnDownloadTaskAndUploadTask() async throws {
        // Given / When
        let downloadCommand = try await DownloadTask {
            BaseURL("example.com")
        }
        .description(.cURL)

        let uploadCommand = try await UploadTask {
            BaseURL("example.com")
        }
        .description(.cURL)

        // Then
        #expect(downloadCommand.contains("'https://example.com'"))
        #expect(uploadCommand.contains("'https://example.com'"))
    }
}
