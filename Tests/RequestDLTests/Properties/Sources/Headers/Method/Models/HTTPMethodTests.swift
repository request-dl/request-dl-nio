/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct HTTPMethodTests {

    @Test
    func getMethodRawValue() async throws {
        #expect(HTTPMethod.get == "GET")
    }

    @Test
    func headMethodRawValue() async throws {
        #expect(HTTPMethod.head == "HEAD")
    }

    @Test
    func postMethodRawValue() async throws {
        #expect(HTTPMethod.post == "POST")
    }

    @Test
    func putMethodRawValue() async throws {
        #expect(HTTPMethod.put == "PUT")
    }

    @Test
    func deleteMethodRawValue() async throws {
        #expect(HTTPMethod.delete == "DELETE")
    }

    @Test
    func connectMethodRawValue() async throws {
        #expect(HTTPMethod.connect == "CONNECT")
    }

    @Test
    func optionsMethodRawValue() async throws {
        #expect(HTTPMethod.options == "OPTIONS")
    }

    @Test
    func traceMethodRawValue() async throws {
        #expect(HTTPMethod.trace == "TRACE")
    }

    @Test
    func patchMethodRawValue() async throws {
        #expect(HTTPMethod.patch == "PATCH")
    }

    @Test
    func method_withStringLossless() async throws {
        // Given
        let method = HTTPMethod.trace

        // When
        let string = String(method)
        let losslessMethod = HTTPMethod(string)

        // Then
        #expect(string == method.description)
        #expect(losslessMethod == method)
    }
}
