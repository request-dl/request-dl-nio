//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDLInternals

struct ZeroingBytesTests {

    @Test
    func zeroingBytes_whenGivenBytes_preservesContentsAndCount() async throws {
        // Given
        let bytes: [UInt8] = [1, 2, 3, 4, 5]

        // When
        let zeroingBytes = ZeroingBytes(bytes)

        // Then
        #expect(zeroingBytes.count == bytes.count)
        #expect(Array(zeroingBytes) == bytes)
    }

    @Test
    func zeroingBytes_whenSameContents_areEqual() async throws {
        // Given
        let lhs = ZeroingBytes([10, 20, 30])
        let rhs = ZeroingBytes([10, 20, 30])

        // Then
        #expect(lhs == rhs)
    }

    @Test
    func zeroingBytes_whenDifferentContents_areNotEqual() async throws {
        // Given
        let lhs = ZeroingBytes([10, 20, 30])
        let rhs = ZeroingBytes([10, 20, 31])

        // Then
        #expect(lhs != rhs)
    }

    @Test
    func zeroingBytes_whenDifferentLengths_areNotEqual() async throws {
        // Given
        let lhs = ZeroingBytes([10, 20, 30])
        let rhs = ZeroingBytes([10, 20])

        // Then
        #expect(lhs != rhs)
    }

    @Test
    func zeroingBytes_whenEmpty_hasZeroCountAndNoElements() async throws {
        // Given
        let zeroingBytes = ZeroingBytes([UInt8]())

        // Then
        #expect(zeroingBytes.count == 0)
        #expect(Array(zeroingBytes).isEmpty)
    }
}
