/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class InternalsAsyncBytesTests: XCTestCase {

    var stream: Internals.AsyncStream<Internals.DataBuffer>?

    override func setUp() async throws {
        try await super.setUp()
        stream = .init()
    }

    override func tearDown() async throws {
        try await super.tearDown()
        stream = nil
    }

    func testAsyncBytes_whenAppendData_shouldContainsAll() async throws {
        // Given
        let stream = try XCTUnwrap(stream)

        let part1 = Data("Hello World".utf8)
        let part2 = Data("Earth is a small planet to live".utf8)

        let bytes = Internals.AsyncBytes(
            totalSize: part1.count + part2.count,
            stream: stream
        )

        // When
        stream.append(.success(Internals.DataBuffer(part1)))
        stream.append(.success(Internals.DataBuffer(part2)))
        stream.close()

        // Them
        let data = try await Data(bytes)

        XCTAssertEqual(data, part1 + part2)
    }

    func testAsyncBytes_whenAppendError_shouldContaiAnyError() async throws {
        // Given
        let stream = try XCTUnwrap(stream)
        
        let part1 = Data("Hello World".utf8)
        let part2 = Data("Earth is a small planet to live".utf8)
        let error = AnyError()

        let bytes = Internals.AsyncBytes(
            totalSize: part1.count + part2.count,
            stream: stream
        )

        // When
        stream.append(.success(Internals.DataBuffer(part1)))
        stream.append(.success(Internals.DataBuffer(part2)))
        stream.append(.failure(error))

        var data = Data()
        var errors = [Error]()

        do {
            for try await item in bytes {
                data.append(item)
            }
        } catch {
            errors.append(error)
        }

        // Them
        XCTAssertEqual(data, part1 + part2)

        XCTAssertEqual(errors.count, 1)
    }
}
