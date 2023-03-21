/*
 See LICENSE for this package's licensing information.
*/

import XCTest
import NIOCore
@testable import RequestDLInternals

class BodySequenceTests: XCTestCase {

    func testBodySequence_whenEmpty_shouldBeEmpty() async throws {
        // Given
        let bodySequence = makeSequence {}

        // When
        let sequence = Array(bodySequence).resolveData()

        // Then
        XCTAssertEqual(sequence, [])
    }

    func testBodySequence_whenContainsDataLessThenSize_shouldBeEqualData() async throws {
        // Given
        let data = Data("Hello World!".utf8)

        let bodySequence = makeSequence(size: 1024) {
            BodyItem(data)
        }

        // When
        let sequence = Array(bodySequence).resolveData()

        // Then
        XCTAssertEqual(sequence, [data])
    }

    func testBodySequence_whenContainsTwoDataLessThenSize_shouldBeEqualParts() async throws {
        // Given
        let part1 = Data("Hello World!".utf8)
        let part2 = Data("Earth is a big planet".utf8)

        let bodySequence = makeSequence(size: 1024) {
            BodyItem(part1)
            BodyItem(part2)
        }

        // When
        let sequence = Array(bodySequence).resolveData()

        // Then
        XCTAssertEqual(sequence, [part1 + part2])
    }

    func testBodySequence_whenContainsTwoDataGreaterThenSize_shouldBeFragmentedIntoParts() async throws {
        // Given
        let part1 = Data("Hello World!".utf8)
        let part2 = Data("Earth is a big planet".utf8)
        let size = 2

        let bodySequence = makeSequence(size: size) {
            BodyItem(part1)
            BodyItem(part2)
        }

        // When
        let sequence = Array(bodySequence).resolveData()
        let expecting = Array(part1 + part2).split(by: size)

        // Then
        XCTAssertEqual(sequence, expecting)
    }

    func testBodySequence_whenContainsFileWithData_shouldContainsAllData() async throws {
        // Given

        let part1 = Data("Hello World!".utf8)
        let part2 = Data("Earth is a big planet".utf8)
        let part3 = Data("Contents in the file".utf8)
        let size = 16

        let bodySequence = makeSequence(size: size) {
            BodyItem(part1)
            BodyItem(part2)
            BodyItem(FileBuffer(part3))
        }

        // When
        let sequence = Array(bodySequence).resolveData()
        let expecting = Array(part1 + part2 + part3).split(by: size)

        // Then
        XCTAssertEqual(sequence, expecting)
    }

    func testBodySequence_whenBiggerDataWithNilSize_shouldFragmentInto10000Parts() async throws {
        // Given
        let length = 20_001
        let fragmentsSize = Int(floor(Double(length) / 10_000))

        let data = Data.randomData(length: length)

        let bodySequence = makeSequence {
            BodyItem(data)
        }

        // When
        let sequence = Array(bodySequence).resolveData()
        let expecting = Array(data).split(by: fragmentsSize)

        // Then
        XCTAssertEqual(sequence, expecting)
    }

    func testBodySequence_whenContainsTrueConditional_shouldBeFirstBlock() async throws {
        // Given
        let condition = true
        let trueData = Data("true".utf8)
        let falseData = Data("false".utf8)

        let bodySequence = makeSequence {
            if condition {
                BodyItem(trueData)
            } else {
                BodyItem(falseData)
            }
        }

        // When
        let data = Array(bodySequence).resolveData()
        let expected = Array(trueData).split(by: 1)

        // Then
        XCTAssertEqual(data, expected)
    }

    func testBodySequence_whenContainsFalseConditional_shouldBeFirstBlock() async throws {
        // Given
        let condition = false
        let trueData = Data("true".utf8)
        let falseData = Data("false".utf8)

        let bodySequence = makeSequence {
            if condition {
                BodyItem(trueData)
            } else {
                BodyItem(falseData)
            }
        }

        // When
        let data = Array(bodySequence).resolveData()
        let expected = Array(falseData).split(by: 1)

        // Then
        XCTAssertEqual(data, expected)
    }

    func testBodySequence_whenOptionalBody_shouldBeResolved() async throws {
        // Given
        let value: Data? = Data("false".utf8)

        let bodySequence = makeSequence {
            if let value {
                BodyItem(value)
            }
        }

        // When
        let data = Array(bodySequence).resolveData()
        let expected = value.map { Array($0).split(by: 1) }

        // Then
        XCTAssertEqual(data, expected)
    }

    func testBodySequence_whenTuple3_shouldBeResolved() async throws {
        // Given
        let value = Data("123".utf8)

        let bodySequence = makeSequence {
            BodyItem([value[0]])
            BodyItem([value[1]])
            BodyItem([value[2]])
        }

        // When
        let data = Array(bodySequence).resolveData()
        let expected = Array(value).split(by: 1)

        // Then
        XCTAssertEqual(data, expected)
    }

    func testBodySequence_whenTuple4_shouldBeResolved() async throws {
        // Given
        let value = Data("1234".utf8)

        let bodySequence = makeSequence {
            BodyItem([value[0]])
            BodyItem([value[1]])
            BodyItem([value[2]])
            BodyItem([value[3]])
        }

        // When
        let data = Array(bodySequence).resolveData()
        let expected = Array(value).split(by: 1)

        // Then
        XCTAssertEqual(data, expected)
    }

    func testBodySequence_whenTuple5_shouldBeResolved() async throws {
        // Given
        let value = Data("12345".utf8)

        let bodySequence = makeSequence {
            BodyItem([value[0]])
            BodyItem([value[1]])
            BodyItem([value[2]])
            BodyItem([value[3]])
            BodyItem([value[4]])
        }

        // When
        let data = Array(bodySequence).resolveData()
        let expected = Array(value).split(by: 1)

        // Then
        XCTAssertEqual(data, expected)
    }

    func testBodySequence_whenTuple6_shouldBeResolved() async throws {
        // Given
        let value = Data("123456".utf8)

        let bodySequence = makeSequence {
            BodyItem([value[0]])
            BodyItem([value[1]])
            BodyItem([value[2]])
            BodyItem([value[3]])
            BodyItem([value[4]])
            BodyItem([value[5]])
        }

        // When
        let data = Array(bodySequence).resolveData()
        let expected = Array(value).split(by: 1)

        // Then
        XCTAssertEqual(data, expected)
    }

    func testBodySequence_whenTuple7_shouldBeResolved() async throws {
        // Given
        let value = Data("1234567".utf8)

        let bodySequence = makeSequence {
            BodyItem([value[0]])
            BodyItem([value[1]])
            BodyItem([value[2]])
            BodyItem([value[3]])
            BodyItem([value[4]])
            BodyItem([value[5]])
            BodyItem([value[6]])
        }

        // When
        let data = Array(bodySequence).resolveData()
        let expected = Array(value).split(by: 1)

        // Then
        XCTAssertEqual(data, expected)
    }

    func testBodySequence_whenTuple8_shouldBeResolved() async throws {
        // Given
        let value = Data("12345678".utf8)

        let bodySequence = makeSequence {
            BodyItem([value[0]])
            BodyItem([value[1]])
            BodyItem([value[2]])
            BodyItem([value[3]])
            BodyItem([value[4]])
            BodyItem([value[5]])
            BodyItem([value[6]])
            BodyItem([value[7]])
        }

        // When
        let data = Array(bodySequence).resolveData()
        let expected = Array(value).split(by: 1)

        // Then
        XCTAssertEqual(data, expected)
    }
}

extension BodySequenceTests {

    func makeSequence<Content: BodyContent>(
        size: Int? = nil,
        @RequestBodyBuilder content: () -> Content
    ) -> BodySequence {
        let context = _ContextBody()
        Content.makeBody(content(), in: context)

        return .init(
            buffers: context.buffers,
            size: size
        )
    }
}
