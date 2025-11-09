/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
import NIOCore
@testable import RequestDL

struct InternalsBodySequenceTests {

    @Test
    func bodySequence_whenEmpty_shouldBeEmpty() async throws {
        // Given
        let bodySequence = makeBodySequence([])

        // When
        let sequence = Array(bodySequence).resolveData()

        // Then
        #expect(sequence == [])
    }

    @Test
    func bodySequence_whenContainsDataLessThenSize_shouldBeEqualData() async throws {
        // Given
        let data = Data("Hello World!".utf8)

        let bodySequence = makeBodySequence(chunkSize: 1024, [
            Internals.DataBuffer(data)
        ])

        // When
        let sequence = Array(bodySequence).resolveData()

        // Then
        #expect(sequence == [data])
    }

    @Test
    func bodySequence_whenContainsTwoDataLessThenSize_shouldBeEqualParts() async throws {
        // Given
        let part1 = Data("Hello World!".utf8)
        let part2 = Data("Earth is a small planet".utf8)

        let bodySequence = makeBodySequence(chunkSize: 1024, [
            Internals.DataBuffer(part1),
            Internals.DataBuffer(part2)
        ])

        // When
        let sequence = Array(bodySequence).resolveData()

        // Then
        #expect(sequence == [part1 + part2])
    }

    @Test
    func bodySequence_whenContainsTwoDataGreaterThenSize_shouldBeFragmentedIntoParts() async throws {
        // Given
        let part1 = Data("Hello World!".utf8)
        let part2 = Data("Earth is a small planet".utf8)
        let chunkSize = 2

        let bodySequence = makeBodySequence(chunkSize: chunkSize, [
            Internals.DataBuffer(part1),
            Internals.DataBuffer(part2)
        ])

        // When
        let sequence = Array(bodySequence).resolveData()
        let expecting = Array(part1 + part2).split(by: chunkSize)

        // Then
        #expect(sequence == expecting)
    }

    @Test
    func bodySequence_whenContainsFileWithData_shouldContainsAllData() async throws {
        // Given

        let part1 = Data("Hello World!".utf8)
        let part2 = Data("Earth is a small planet".utf8)
        let part3 = Data("Contents in the file".utf8)
        let chunkSize = 16

        let bodySequence = makeBodySequence(chunkSize: chunkSize, [
            Internals.DataBuffer(part1),
            Internals.DataBuffer(part2),
            Internals.FileBuffer(part3)
        ])

        // When
        let sequence = Array(bodySequence).resolveData()
        let expecting = Array(part1 + part2 + part3).split(by: chunkSize)

        // Then
        #expect(sequence == expecting)
    }

    @Test
    func bodySequence_whenBiggerDataWithNilSize_shouldFragmentInto10000Parts() async throws {
        // Given
        let length = 20_001
        let chunkSize = Int(floor(Double(length) / 10_000))

        let data = Data.randomData(length: length)

        let bodySequence = makeBodySequence([
            Internals.DataBuffer(data)
        ])

        // When
        let sequence = Array(bodySequence).resolveData()
        let expecting = Array(data).split(by: chunkSize)

        // Then
        #expect(sequence == expecting)
    }
}

extension InternalsBodySequenceTests {

    func makeBodySequence(
        chunkSize: Int? = nil,
        _ buffers: [Internals.AnyBuffer]
    ) -> Internals.BodySequence {
        return .init(
            chunkSize: chunkSize,
            buffers: buffers
        )
    }
}
