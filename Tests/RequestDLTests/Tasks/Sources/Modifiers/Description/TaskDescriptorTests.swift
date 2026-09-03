//
// See LICENSE for this package's licensing information.
//

import SwiftAsyncStream
import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.UUID
#endif

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

    /// `final class ... : @unchecked Sendable` guarded by `Lock` -- the same pattern
    /// `ModifiersProgressTests` uses to capture state from a `@Sendable` callback.
    private final class Box<Value: Sendable>: @unchecked Sendable {

        var value: Value {
            lock.withLock { _value }
        }

        private let lock = Lock()
        private var _value: Value

        init(_ value: Value) {
            _value = value
        }

        func set(_ value: Value) {
            lock.withLock { _value = value }
        }
    }

    @Test
    func onDescribeReceivesDescriptorOutputAndTaskStillPerformsTheRequest() async throws {
        // Given
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString

        let certificate = Certificates().server()
        let output = "Hello World"

        let response = try LocalServer.ResponseConfiguration(jsonObject: output)
        localServer.cleanup(at: uri)
        localServer.insert(response, at: uri)
        defer { localServer.cleanup(at: uri) }

        let capturedDescription = Box<(url: String, method: String?)?>(nil)

        // When
        let task = DataTask {
            BaseURL(localServer.baseURL)
            Path(uri)

            Session.localServer

            SecureConnection {
                TrustRoots(certificate.certificateURL.absolutePath(percentEncoded: false))
            }
        }
        .description(URLAndMethodDescriptor()) { description in
            capturedDescription.set(description)
        }

        // Then -- composing the task runs nothing by itself; `onDescribe` only fires once the
        // task is actually performed, the same way a `RequestTaskModifier` defers its `body(_:)`.
        #expect(capturedDescription.value == nil)

        let taskResult = try await task.result()
        let result = try HTTPResult<String>(taskResult.payload)

        // Then -- `onDescribe` ran with the resolved request, and the real request also went
        // through and produced its own result.
        #expect(capturedDescription.value?.url == "https://" + localServer.baseURL + uri)
        #expect(result.response == output)
    }

    @Test
    func onDescribeIsSkippedWhenDisabled() async throws {
        // Given
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString

        let certificate = Certificates().server()
        let output = "Hello World"

        let response = try LocalServer.ResponseConfiguration(jsonObject: output)
        localServer.cleanup(at: uri)
        localServer.insert(response, at: uri)
        defer { localServer.cleanup(at: uri) }

        let wasCalled = Box(false)

        // When
        let taskResult = try await DataTask {
            BaseURL(localServer.baseURL)
            Path(uri)

            Session.localServer

            SecureConnection {
                TrustRoots(certificate.certificateURL.absolutePath(percentEncoded: false))
            }
        }
        .description(URLAndMethodDescriptor(), enabled: false) { _ in
            wasCalled.set(true)
        }
        .result()

        let result = try HTTPResult<String>(taskResult.payload)

        // Then -- disabling the descriptor pass doesn't stop the real request from completing.
        #expect(!wasCalled.value)
        #expect(result.response == output)
    }
}
