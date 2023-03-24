/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDLInternals

class BodyItemTests: XCTestCase {

    var context: _ContextBody!

    override func setUp() async throws {
        try await super.setUp()
        context = .init()
    }

    override func tearDown() async throws {
        try await super.tearDown()
        context = nil
    }

    func testBodyItem_whenInitDataBuffer_shouldBeValid() async throws {
        // Given
        let data = Data("Hello World!".utf8)
        let item = BodyItem(DataBuffer(data))

        // When
        var buffer = item.resolve(context)
        let result = buffer.readData(buffer.readableBytes)

        // Then
        XCTAssertEqual(result, data)
    }

    func testBodyItem_whenInitStaticString_shouldBeValid() async throws {
        // Given
        let string: StaticString = "Hello world"
        let item = BodyItem(string)

        // When
        var buffer = item.resolve(context)
        let result = buffer.readData(buffer.readableBytes)

        // Then
        XCTAssertEqual(result, Data(
            bytes: string.utf8Start,
            count: string.utf8CodeUnitCount
        ))
    }

    func testBodyItem_whenInitString_shouldBeValid() async throws {
        // Given
        let string: String = "Hello world"
        let item = BodyItem(string)

        // When
        var buffer = item.resolve(context)
        let result = buffer.readData(buffer.readableBytes)

        // Then
        XCTAssertEqual(result, Data(string.utf8))
    }

    func testBodyItem_whenInitByteURL_shouldBeValid() async throws {
        // Given
        let byteURL = ByteURL()
        let data = Data("Hello world".utf8)
        try data.write(to: byteURL)

        let item = BodyItem(byteURL)

        // When
        var buffer = item.resolve(context)
        let result = buffer.readData(buffer.readableBytes)

        // Then
        XCTAssertEqual(result, data)
    }

    func testBodyItem_whenInitURL_shouldBeValid() async throws {
        // Given
        let url = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("InitURL.text")

        defer { try? FileManager.default.removeItem(at: url) }

        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }

        let data = Data("Hello world".utf8)
        try data.write(to: url)

        let item = BodyItem(url)

        // When
        var buffer = item.resolve(context)
        let result = buffer.readData(buffer.readableBytes)

        // Then
        XCTAssertEqual(result, data)
    }

    func testBodyItem_whenInitSequence_shouldBeValid() async throws {
        // Given
        let data = Data("Hello world".utf8)
        let item = BodyItem(BytesSequence(data))

        // When
        var buffer = item.resolve(context)
        let result = buffer.readData(buffer.readableBytes)

        // Then
        XCTAssertEqual(result, data)
    }

    func testBodyItem_whenInitData_shouldBeValid() async throws {
        // Given
        let data = Data("Hello world".utf8)
        let item = BodyItem(data)

        // When
        var buffer = item.resolve(context)
        let result = buffer.readData(buffer.readableBytes)

        // Then
        XCTAssertEqual(result, data)
    }
}

private extension BodyItem {

    func resolve(_ context: _ContextBody) -> BufferProtocol {
        BodyItem.makeBody(self, in: context)
        return context.buffers[0]
    }
}
