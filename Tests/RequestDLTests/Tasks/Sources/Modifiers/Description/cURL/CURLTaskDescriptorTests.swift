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

/// No `LocalServer` anywhere here: `.description(_:)` only resolves the `Property` graph
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

        // Then: one `-F` per field, not a flattened blob.
        #expect(command.contains(#"--form-string 'name=John Doe'"#))
        #expect(command.contains("-F 'avatar=@avatar.png;type=image/png'"))

        // The multipart body's own `Content-Type` (with its now-irrelevant boundary) must not
        // leak into a generic `-H`, since curl derives its own from `-F`.
        #expect(!command.contains("multipart/form-data"))
    }

    /// A plain (no `filename`) form field's bytes aren't necessarily valid UTF-8, e.g. binary
    /// `Data` handed to `Form` without a filename. They must not be lossily decoded to `String`
    /// (replacing anything invalid with U+FFFD) before reaching `curlShellQuote`'s own
    /// byte-safe fallback, which would silently corrupt the value.
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

    // MARK: - Method

    private func describe(method: String) async throws -> String {
        var configuration = RequestConfiguration()
        configuration.baseURL = "https://example.com"
        configuration.method = method

        return try await CURLTaskDescriptor().describe(
            TaskDescriptorContext(requestConfiguration: configuration, formFields: [])
        )
    }

    /// `-X` takes the method as the shell reads it: one with a space, a `;` or a newline in it is
    /// another argument, another command, or two lines, and was written as it was.
    @Test(arguments: [
        ("GET / HTTP/1.1\r\nX: y\r\n\r\nPOST", #"-X $'\x47\x45\x54"#),
        ("GET; touch /tmp/x", "-X 'GET; touch /tmp/x'"),
        ("GET $(id)", "-X 'GET $(id)'"),
        ("GE'T", #"-X $'\x47\x45\x27\x54'"#),
        ("", "-X ''"),
    ])
    func methodThatIsNotAPlainWordIsQuoted(_ method: String, _ expected: String) async throws {
        let command = try await describe(method: method)

        #expect(command.contains(expected))
        #expect(!command.contains("\r"))
        #expect(!command.contains("HTTP/1.1"))
        #expect(command.split(separator: "\n", omittingEmptySubsequences: false).count == 3)
    }

    @Test(arguments: ["GET", "POST", "PATCH", "M-SEARCH", "X_CUSTOM"])
    func plainMethodStaysBare(_ method: String) async throws {
        let command = try await describe(method: method)

        #expect(command.contains("-X \(method) \\\n"))
    }

    // MARK: - Form fields

    /// `-F 'name=@path'` reads a file and `-F 'name=<path'` its content, and `;type=` is a
    /// parameter: a text field that starts with `@` or `<`, or has one, was a different field once
    /// the description was pasted.
    @Test(arguments: [
        "@/etc/passwd",
        "<secret.txt",
        "x;type=text/html",
        "plain",
    ])
    func textFormFieldIsWrittenAsFormString(_ value: String) async throws {
        var configuration = RequestConfiguration()
        configuration.baseURL = "https://example.com"

        let field = FormFieldDescriptor(
            name: "note",
            filename: nil,
            contentType: "text/plain",
            content: Data(value.utf8)
        )

        let command = try await CURLTaskDescriptor().describe(
            TaskDescriptorContext(requestConfiguration: configuration, formFields: [field])
        )

        #expect(command.contains("--form-string " + curlShellQuote("note=\(value)")))
        #expect(!command.contains("-F "))
    }

    @Test
    func formFieldDescriptionRoundTripsAsTextThroughCURLCommandParser() async throws {
        let command = try await DataTask {
            BaseURL("example.com")
            Form(name: "note", verbatim: "@/etc/passwd")
        }
        .description(.cURL)

        // `allowing: []`: nothing here reads a file.
        let parsed = try await CURLCommandParser.parseCommand(command, allowing: []).requestConfiguration
        let body = try #require(parsed.body)
        var data = Data()

        for try await chunk in body {
            data.append(chunk)
        }

        let text = String(decoding: data, as: UTF8.self)

        #expect(text.contains("@/etc/passwd"))
        #expect(!text.contains("filename="))
    }
}
