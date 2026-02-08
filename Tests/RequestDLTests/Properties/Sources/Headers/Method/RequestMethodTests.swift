/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct RequestMethodTests {

    @Test
    func getHTTPMethod() async throws {
        let property = TestProperty(RequestMethod(.get))
        let resolved = try await resolve(property)
        #expect(resolved.requestConfiguration.method == "GET")
    }

    @Test
    func headHTTPMethod() async throws {
        let property = TestProperty(RequestMethod(.head))
        let resolved = try await resolve(property)
        #expect(resolved.requestConfiguration.method == "HEAD")
    }

    @Test
    func postHTTPMethod() async throws {
        let property = TestProperty(RequestMethod(.post))
        let resolved = try await resolve(property)
        #expect(resolved.requestConfiguration.method == "POST")
    }

    @Test
    func putHTTPMethod() async throws {
        let property = TestProperty(RequestMethod(.put))
        let resolved = try await resolve(property)
        #expect(resolved.requestConfiguration.method == "PUT")
    }

    @Test
    func deleteHTTPMethod() async throws {
        let property = TestProperty(RequestMethod(.delete))
        let resolved = try await resolve(property)
        #expect(resolved.requestConfiguration.method == "DELETE")
    }

    @Test
    func connectHTTPMethod() async throws {
        let property = TestProperty(RequestMethod(.connect))
        let resolved = try await resolve(property)
        #expect(resolved.requestConfiguration.method == "CONNECT")
    }

    @Test
    func optionsHTTPMethod() async throws {
        let property = TestProperty(RequestMethod(.options))
        let resolved = try await resolve(property)
        #expect(resolved.requestConfiguration.method == "OPTIONS")
    }

    @Test
    func traceHTTPMethod() async throws {
        let property = TestProperty(RequestMethod(.trace))
        let resolved = try await resolve(property)
        #expect(resolved.requestConfiguration.method == "TRACE")
    }

    @Test
    func patchHTTPMethod() async throws {
        let property = TestProperty(RequestMethod(.patch))
        let resolved = try await resolve(property)
        #expect(resolved.requestConfiguration.method == "PATCH")
    }

    @Test
    func neverBody() async throws {
        // Given
        let property = RequestMethod(.get)

        // Then
        try await assertNever(property.body)
    }
}
