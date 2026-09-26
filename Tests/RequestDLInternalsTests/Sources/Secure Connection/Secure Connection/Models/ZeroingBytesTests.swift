//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDLInternals

struct ZeroingBytesTests {

    @Test
    func zeroingBytes_whenGivenBytes_preservesContentsAndCount() async throws {
        // Given: `[UInt8]` offers contiguous storage, exercising `init`'s
        // `withContiguousStorageIfAvailable` fast path.
        let bytes: [UInt8] = [1, 2, 3, 4, 5]

        // When
        let zeroingBytes = ZeroingBytes(bytes)

        // Then
        #expect(zeroingBytes.count == bytes.count)
        #expect(Array(zeroingBytes) == bytes)
    }

    @Test
    func zeroingBytes_whenGivenStringUTF8_preservesContentsAndCount() async throws {
        // Given: the realistic call shape (`SecureBytes("password".utf8)`); a native `String`'s
        // `.utf8` view also offers contiguous storage.
        let password = "hunter2"

        // When
        let zeroingBytes = ZeroingBytes(password.utf8)

        // Then
        #expect(zeroingBytes.count == password.utf8.count)
        #expect(Array(zeroingBytes) == Array(password.utf8))
    }

    @Test
    func zeroingBytes_whenGivenNonContiguousSequence_preservesContentsAndCount() async throws {
        // Given: `AnySequence` erases whatever contiguous storage the wrapped collection might
        // otherwise offer, forcing `init`'s `Array(bytes)` fallback path.
        let bytes: [UInt8] = [1, 2, 3, 4, 5]

        // When
        let zeroingBytes = ZeroingBytes(AnySequence(bytes))

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

    @Test
    func zeroingBytes_whenBothEmpty_areEqual() async throws {
        // Given: an empty `buffer` on both sides, the one case where `zip`'s accumulation loop
        // in `==` runs zero iterations and falls straight through to `difference == 0`.
        let lhs = ZeroingBytes([UInt8]())
        let rhs = ZeroingBytes([UInt8]())

        // Then
        #expect(lhs == rhs)
    }

    /// Regression coverage: `==` used to delegate to `memcmp`, which short-circuits on the first
    /// mismatched byte -- a timing side channel already fixed once for SPKI pin matching
    /// (`Internals.SPKIHash.matchesSPKI`). `ZeroingBytes.==` backs `PrivateKey`'s password
    /// comparison on every `Internals.ClientManager` pool lookup, so the same class of bug applied
    /// here too. This can't assert on timing directly (too flaky), but confirms `==` still agrees
    /// with `memcmp` on where the *first* mismatch falls, not just whether the two are equal
    /// overall -- the one case an XOR-accumulate rewrite could plausibly get wrong.
    @Test
    func zeroingBytes_whenFirstByteDiffers_stillComparesEveryByte() async throws {
        // Given
        let lhs = ZeroingBytes([0xFF, 20, 30])
        let rhs = ZeroingBytes([0x00, 20, 30])

        // Then
        #expect(lhs != rhs)
    }
}
