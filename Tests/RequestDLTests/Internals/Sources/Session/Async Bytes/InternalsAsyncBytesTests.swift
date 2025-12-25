/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct InternalsAsyncBytesTests {

    @Test
    func asyncBytes_whenAppendData_shouldContainsAll() async throws {
        // Given
        let stream = Internals.AsyncStream<Internals.DataBuffer>()

        let part1 = Data("Hello World".utf8)
        let part2 = Data("Earth is a small planet to live".utf8)

        let bytes = Internals.AsyncBytes(
            logger: nil,
            totalSize: part1.count + part2.count,
            stream: stream
        )

        // When
        stream.append(.success(Internals.DataBuffer(part1)))
        stream.append(.success(Internals.DataBuffer(part2)))
        stream.close()

        // Them
        let data = try await Data(bytes)

        #expect(data == part1 + part2)
    }

    @Test
    func asyncBytes_whenAppendError_shouldContaiAnyError() async throws {
        // Given
        let stream = Internals.AsyncStream<Internals.DataBuffer>()

        let part1 = Data("Hello World".utf8)
        let part2 = Data("Earth is a small planet to live".utf8)
        let error = AnyError()

        let bytes = Internals.AsyncBytes(
            logger: nil,
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
        #expect(data == part1 + part2)

        #expect(errors.count == 1)
    }
}
