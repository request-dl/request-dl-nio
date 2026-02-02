/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct SPKIHashSourceTests {

    @Test
    func validBase64Normalizes() throws {
        let source = SPKIHashSource.base64String("abc123+/abc123+/abc123+/abc123+/abc123+/abc123+/abc==")
        let result = try source.base64EncodedString()
        #expect(result == "abc123+/abc123+/abc123+/abc123+/abc123+/abc123+/abc==")
    }

    @Test
    func base64WithWhitespaceNormalizes() throws {
        let source = SPKIHashSource.base64String("  abc123+/abc123+/abc123+/abc123+/abc123+/abc123+/abc==\n\t")
        let result = try source.base64EncodedString()
        #expect(result == "abc123+/abc123+/abc123+/abc123+/abc123+/abc123+/abc==")
    }

    @Test
    func invalidBase64Throws() throws {
        let string = "invalid!base64@string#"
        let source = SPKIHashSource.base64String(string)
        #expect(throws: SPKIHashError.invalidBase64(string)) {
            _ = try source.base64EncodedString()
        }
    }

    @Test
    func base64WrongLengthThrows() throws {
        // 20 bytes = SHA-1 length (invalid for SPKI pinning)
        let sha1Hash = Data(repeating: 0x00, count: 20).base64EncodedString()
        let source = SPKIHashSource.base64String(sha1Hash)
        #expect(throws: SPKIHashError.invalidLength(expected: 32, got: 20)) {
            _ = try source.base64EncodedString()
        }
    }

    @Test
    func validRawDataConverts() throws {
        let data = Data(repeating: 0x42, count: 32) // Exactly 32 bytes
        let source = SPKIHashSource.rawData(data)
        let result = try source.base64EncodedString()
        #expect(result == "QkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkI=")
    }

    @Test
    func rawDataWrongLengthThrows() throws {
        let shortData = Data(repeating: 0x00, count: 31)
        let source = SPKIHashSource.rawData(shortData)
        #expect(throws: SPKIHashError.invalidLength(expected: 32, got: 31)) {
            _ = try source.base64EncodedString()
        }

        let longData = Data(repeating: 0x00, count: 33)
        let source2 = SPKIHashSource.rawData(longData)
        #expect(throws: SPKIHashError.invalidLength(expected: 32, got: 33)) {
            _ = try source2.base64EncodedString()
        }
    }

    @Test
    func hashableConformance() {
        let source1 = SPKIHashSource.base64String("abc123==")
        let source2 = SPKIHashSource.base64String("abc123==")
        let source3 = SPKIHashSource.base64String("different")

        #expect(source1 == source2)
        #expect(source1.hashValue == source2.hashValue)
        #expect(source1 != source3)
    }
}
