//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL

/// `CURLTaskDescriptor` is only the first conformance -- this proves the mechanism underneath
/// `.description(_:)` (`TaskDescriptorContext`, and `FormNode`'s contribution to it) carries no
/// curl-specific coupling, by conforming a second, unrelated `TaskDescriptor` right here in the
/// test target.
private struct FieldNamesDescriptor: TaskDescriptor {

    func describe(_ context: TaskDescriptorContext) async throws -> [String] {
        context.formFields.map(\.name)
    }
}

private struct URLAndMethodDescriptor: TaskDescriptor {

    func describe(_ context: TaskDescriptorContext) async throws -> (url: String, method: String?) {
        (context.requestConfiguration.url, context.requestConfiguration.method)
    }
}

struct TaskDescriptorTests {

    @Test
    func customDescriptorReceivesResolvedConfiguration() async throws {
        // Given / When
        let result = try await DataTask {
            BaseURL("example.com")
            Path("users")
            RequestMethod(.post)
        }
        .description(URLAndMethodDescriptor())

        // Then
        #expect(result.url == "https://example.com/users")
        #expect(result.method == "POST")
    }

    @Test
    func customDescriptorReceivesFormFieldsCapturedBeforeFlattening() async throws {
        // Given / When
        let fieldNames = try await DataTask {
            BaseURL("example.com")
            Form(name: "first", verbatim: "1")
            Form(name: "second", verbatim: "2")
        }
        .description(FieldNamesDescriptor())

        // Then
        #expect(fieldNames == ["first", "second"])
    }

    @Test
    func formFieldsAreEmptyWhenNoFormIsDeclared() async throws {
        // Given / When
        let fieldNames = try await DataTask {
            BaseURL("example.com")
        }
        .description(FieldNamesDescriptor())

        // Then
        #expect(fieldNames.isEmpty)
    }
}
