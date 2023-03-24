/*
 See LICENSE for this package's licensing information.
*/

import XCTest
import NIOCore
@testable import RequestDLInternals

// swiftlint:disable type_body_length file_length
class DataBufferTests: XCTestCase {

    var byteURL: ByteURL!

    override func setUp() async throws {
        try await super.setUp()

        byteURL = ByteURL()
    }

    override func tearDown() async throws {
        try await super.tearDown()

        byteURL = nil
    }

    func testDataBuffer_whenInitURL_shouldBeEmpty() async throws {
        // Given
        let dataBuffer = DataBuffer(byteURL)

        // When
        let writerIndex = dataBuffer.writerIndex
        let readerIndex = dataBuffer.readerIndex
        let readableBytes = dataBuffer.readableBytes
        let writableBytes = dataBuffer.writableBytes
        let estimatedBytes = dataBuffer.estimatedBytes

        // Then
        XCTAssertEqual(writerIndex, .zero)
        XCTAssertEqual(readerIndex, .zero)
        XCTAssertEqual(readableBytes, .zero)
        XCTAssertEqual(writableBytes, .zero)
        XCTAssertEqual(estimatedBytes, .zero)
    }

    func testDataBuffer_whenContainsData_shouldWriterBeAtEndAndReaderAtZero() async throws {
        // Given
        let data = Data("Hello world".utf8)
        try data.write(to: byteURL)

        let dataBuffer = DataBuffer(byteURL)

        // When
        let writerIndex = dataBuffer.writerIndex
        let readerIndex = dataBuffer.readerIndex
        let readableBytes = dataBuffer.readableBytes
        let writableBytes = dataBuffer.writableBytes

        // Then
        XCTAssertEqual(writerIndex, data.count)
        XCTAssertEqual(readerIndex, .zero)
        XCTAssertEqual(readableBytes, data.count)
        XCTAssertEqual(writableBytes, .zero)
    }

    func testDataBuffer_whenContainsData_shouldReadDataAvailable() async throws {
        // Given
        let data = Data("Hello world".utf8)
        try data.write(to: byteURL)

        var dataBuffer = DataBuffer(byteURL)

        // When
        let readedData = dataBuffer.readData(data.count)

        // Then
        XCTAssertEqual(dataBuffer.writerIndex, data.count)
        XCTAssertEqual(dataBuffer.readerIndex, data.count)
        XCTAssertEqual(dataBuffer.readableBytes, .zero)
        XCTAssertEqual(dataBuffer.writableBytes, .zero)
        XCTAssertEqual(readedData, data)
        XCTAssertEqual(dataBuffer.estimatedBytes, data.count)
    }

    func testDataBuffer_whenContainsDataMovingReaderIndex_shouldReadableBytesBeUpdated() async throws {
        // Given
        let data = Data("Hello world".utf8)
        try data.write(to: byteURL)

        let index = 2
        var dataBuffer = DataBuffer(byteURL)

        // When
        let readableIndex = dataBuffer.readableBytes
        dataBuffer.moveReaderIndex(to: index)

        // Then
        XCTAssertEqual(readableIndex, data.count)
        XCTAssertEqual(dataBuffer.writerIndex, data.count)
        XCTAssertEqual(dataBuffer.readerIndex, index)
        XCTAssertEqual(dataBuffer.readableBytes, data.count - index)
        XCTAssertEqual(dataBuffer.writableBytes, .zero)
    }

    func testDataBuffer_whenContainsDataMovingWriterIndex_shouldWritableBytesBeUpdated() async throws {
        // Given
        let data = Data("Hello world".utf8)
        try data.write(to: byteURL)

        let index = data.count - 2
        var dataBuffer = DataBuffer(byteURL)

        // When
        let writableBytes = dataBuffer.writableBytes
        dataBuffer.moveWriterIndex(to: index)

        // Then
        XCTAssertEqual(writableBytes, .zero)
        XCTAssertEqual(dataBuffer.writerIndex, index)
        XCTAssertEqual(dataBuffer.readerIndex, .zero)
        XCTAssertEqual(dataBuffer.readableBytes, index)
        XCTAssertEqual(dataBuffer.writableBytes, data.count - index)
    }

    func testDataBuffer_whenWritingWithTwoCopy_shouldWritableBytesBeUpdated() async throws {
        // Given
        let data = Data("Hello World".utf8)
        let sut1 = DataBuffer(byteURL)
        var sut2 = sut1

        // When
        let writerIndex = sut1.writerIndex
        let readerIndex = sut1.readerIndex

        sut2.writeData(data)

        // Then
        XCTAssertEqual(writerIndex, sut1.writerIndex)
        XCTAssertEqual(readerIndex, sut1.readerIndex)
        XCTAssertEqual(sut2.writerIndex, data.count)
        XCTAssertEqual(sut2.readableBytes, data.count)
        XCTAssertEqual(sut1.writableBytes, data.count)
        XCTAssertEqual(sut1.readableBytes, .zero)
    }

    func testDataBuffer_whenWritingWithTwoInstances_shouldWritableBytesBeUpdated() async throws {
        // Given
        let data = Data("Hello World".utf8)
        let sut1 = DataBuffer(byteURL)
        var sut2 = DataBuffer(byteURL)

        // When
        let writerIndex = sut1.writerIndex
        let readerIndex = sut1.readerIndex

        sut2.writeData(data)

        // Then
        XCTAssertEqual(writerIndex, sut1.writerIndex)
        XCTAssertEqual(readerIndex, sut1.readerIndex)
        XCTAssertEqual(sut2.writerIndex, data.count)
        XCTAssertEqual(sut2.readableBytes, data.count)
        XCTAssertEqual(sut1.writableBytes, data.count)
        XCTAssertEqual(sut1.readableBytes, .zero)
    }

    func testDataBuffer_whenWritingWithTwoInstancesSimultaneos_shouldWritableBytesBeUpdated() async throws {
        // Given
        let data = Data("Hello World".utf8)
        let writeSliceIndex = 3
        var sut1 = DataBuffer(byteURL)
        var sut2 = DataBuffer(byteURL)

        // When
        sut2.writeData(data)
        sut1.writeData(data[0..<writeSliceIndex])

        // Then
        XCTAssertEqual(sut2.writerIndex, data.count)
        XCTAssertEqual(sut2.readableBytes, data.count)
        XCTAssertEqual(sut1.writableBytes, data.count - writeSliceIndex)
        XCTAssertEqual(sut1.readableBytes, writeSliceIndex)
    }

    func testDataBuffer_whenWritingWithTwoInstancesSimultaneosBytes_shouldWritableBytesBeUpdated() async throws {
        // Given
        let data = Data("Hello World".utf8)
        let writeSliceIndex = 3
        var sut1 = DataBuffer(byteURL)
        var sut2 = DataBuffer(byteURL)

        // When
        sut2.writeBytes(data)
        sut1.writeBytes(data[0..<writeSliceIndex])

        // Then
        XCTAssertEqual(sut2.writerIndex, data.count)
        XCTAssertEqual(sut2.readableBytes, data.count)
        XCTAssertEqual(sut1.writableBytes, data.count - writeSliceIndex)
        XCTAssertEqual(sut1.readableBytes, writeSliceIndex)
    }

    func testDataBuffer_whenReadingWithTwoCopy_shouldReadableBytesBeUpdated() async throws {
        // Given
        let data = Data("Hello World".utf8)
        try data.write(to: byteURL)

        let sut1 = DataBuffer(byteURL)
        var sut2 = sut1

        // When
        let writerIndex = sut1.writerIndex
        let readerIndex = sut1.readerIndex

        let readedData = sut2.readData(data.count)

        // Then
        XCTAssertEqual(readedData, data)
        XCTAssertEqual(writerIndex, data.count)
        XCTAssertEqual(readerIndex, .zero)
        XCTAssertEqual(sut2.writerIndex, data.count)
        XCTAssertEqual(sut2.readableBytes, .zero)
        XCTAssertEqual(sut1.writableBytes, .zero)
        XCTAssertEqual(sut1.readableBytes, data.count)
    }

    func testDataBuffer_whenReadingWithTwoInstances_shouldReadableBytesBeUpdated() async throws {
        // Given
        let data = Data("Hello World".utf8)
        try data.write(to: byteURL)

        let sut1 = DataBuffer(byteURL)
        var sut2 = DataBuffer(byteURL)

        // When
        let writerIndex = sut1.writerIndex
        let readerIndex = sut1.readerIndex

        let readedData = sut2.readData(data.count)

        // Then
        XCTAssertEqual(readedData, data)
        XCTAssertEqual(writerIndex, data.count)
        XCTAssertEqual(readerIndex, .zero)
        XCTAssertEqual(sut2.writerIndex, data.count)
        XCTAssertEqual(sut2.readableBytes, .zero)
        XCTAssertEqual(sut1.writableBytes, .zero)
        XCTAssertEqual(sut1.readableBytes, data.count)
    }

    func testDataBuffer_whenReadingWithTwoInstancesSimultaneos_shouldReadableBytesBeUpdated() async throws {
        // Given
        let data = Data("Hello World".utf8)
        try data.write(to: byteURL)

        let readSliceIndex = 3
        var sut1 = DataBuffer(byteURL)
        var sut2 = DataBuffer(byteURL)

        // When
        let readedData2 = sut2.readData(data.count)
        let readedData1 = sut1.readData(readSliceIndex)

        // Then
        XCTAssertEqual(readedData1, data[0..<readSliceIndex])
        XCTAssertEqual(sut1.writerIndex, data.count)
        XCTAssertEqual(sut1.readableBytes, data.count - readSliceIndex)
        XCTAssertEqual(sut1.writableBytes, .zero)

        XCTAssertEqual(readedData2, data)
        XCTAssertEqual(sut2.writerIndex, data.count)
        XCTAssertEqual(sut2.readableBytes, .zero)
        XCTAssertEqual(sut2.writableBytes, .zero)
    }

    func testDataBuffer_whenReadingWithTwoInstancesSimultaneosBytes_shouldReadableBytesBeUpdated() async throws {
        // Given
        let data = Data("Hello World".utf8)
        try data.write(to: byteURL)

        let readSliceIndex = 3
        var sut1 = DataBuffer(byteURL)
        var sut2 = DataBuffer(byteURL)

        // When
        let readedBytes2 = sut2.readBytes(data.count)
        let readedBytes1 = sut1.readBytes(readSliceIndex)

        // Then
        XCTAssertEqual(readedBytes1, Array(data[0..<readSliceIndex]))
        XCTAssertEqual(sut1.writerIndex, data.count)
        XCTAssertEqual(sut1.readableBytes, data.count - readSliceIndex)
        XCTAssertEqual(sut1.writableBytes, .zero)

        XCTAssertEqual(readedBytes2, Array(data))
        XCTAssertEqual(sut2.writerIndex, data.count)
        XCTAssertEqual(sut2.readableBytes, .zero)
        XCTAssertEqual(sut2.writableBytes, .zero)
    }

    func testDataBuffer_whenWritingAndReadingSimultaneos_shouldBytesBeUpdatedAndOverrided() async throws {
        // Given
        let data = Data("Hello World".utf8)
        let overrideData = Data("Earth".utf8)

        var sut1 = DataBuffer(byteURL)
        var sut2 = DataBuffer(byteURL)

        // When
        sut2.writeData(data)
        let readedDataBeforeOverride2 = sut2.readData(data.count)

        sut1.writeData(overrideData)
        let readedData2 = sut1.readData(sut1.readableBytes)

        sut2.moveReaderIndex(to: .zero)
        let readedDataAfterOverride2 = sut2.readData(sut2.readableBytes)

        // Then
        XCTAssertEqual(readedDataBeforeOverride2, data)
        XCTAssertEqual(readedData2, overrideData)
        XCTAssertEqual(readedDataAfterOverride2, overrideData + data[overrideData.count..<data.count])

        XCTAssertEqual(sut1.writerIndex, overrideData.count)
        XCTAssertEqual(sut1.readerIndex, overrideData.count)
        XCTAssertEqual(sut1.writableBytes, data.count - overrideData.count)
        XCTAssertEqual(sut1.readableBytes, .zero)

        XCTAssertEqual(sut2.writerIndex, data.count)
        XCTAssertEqual(sut2.readerIndex, data.count)
        XCTAssertEqual(sut2.writableBytes, .zero)
        XCTAssertEqual(sut2.readableBytes, .zero)
    }

    func testDataBuffer_whenWritingFromOtherDataBuffer_shouldHaveContentsAppended() async throws {
        // Given
        let otherByteURL = ByteURL()

        let data = Data("Hello World".utf8)
        let otherData = Data("Earth is a small planet to live".utf8)

        var sut1 = DataBuffer(byteURL)
        var sut2 = DataBuffer(otherByteURL)

        // When
        sut1.writeData(data)
        sut2.writeData(otherData)

        sut1.writeBuffer(&sut2)

        // Then
        XCTAssertEqual(sut1.writerIndex, data.count + otherData.count)
        XCTAssertEqual(sut2.writerIndex, otherData.count)

        XCTAssertEqual(sut1.writableBytes, .zero)
        XCTAssertEqual(sut2.writableBytes, .zero)

        XCTAssertEqual(sut1.readerIndex, .zero)
        XCTAssertEqual(sut2.readerIndex, otherData.count)

        XCTAssertEqual(sut1.readData(sut1.readableBytes), data + otherData)
    }

    func testDataBuffer_whenInitEmpty_shouldBeEmpty() async throws {
        // Given
        let dataBuffer = DataBuffer()

        // When
        let writerIndex = dataBuffer.writerIndex
        let readerIndex = dataBuffer.readerIndex
        let readableBytes = dataBuffer.readableBytes
        let writableBytes = dataBuffer.writableBytes

        // Then
        XCTAssertEqual(writerIndex, .zero)
        XCTAssertEqual(readerIndex, .zero)
        XCTAssertEqual(readableBytes, .zero)
        XCTAssertEqual(writableBytes, .zero)
    }

    func testDataBuffer_whenInitData_shouldReadContents() async throws {
        // Given
        let data = Data("Hello World".utf8)
        var dataBuffer = DataBuffer(data)

        // When
        let readedData = dataBuffer.readData(dataBuffer.readableBytes)

        // Then
        XCTAssertEqual(readedData, data)
        XCTAssertEqual(dataBuffer.writerIndex, data.count)
        XCTAssertEqual(dataBuffer.readerIndex, data.count)
        XCTAssertEqual(dataBuffer.readableBytes, .zero)
        XCTAssertEqual(dataBuffer.writableBytes, .zero)
    }

    func testDataBuffer_whenInitBytes_shouldReadContents() async throws {
        // Given
        let bytes = Array(Data("Hello World".utf8))
        var dataBuffer = DataBuffer(bytes)

        // When
        let readedBytes = dataBuffer.readBytes(dataBuffer.readableBytes)

        // Then
        XCTAssertEqual(readedBytes, bytes)
        XCTAssertEqual(dataBuffer.writerIndex, bytes.count)
        XCTAssertEqual(dataBuffer.readerIndex, bytes.count)
        XCTAssertEqual(dataBuffer.readableBytes, .zero)
        XCTAssertEqual(dataBuffer.writableBytes, .zero)
    }

    func testDataBuffer_whenInitString_shouldReadContents() async throws {
        // Given
        let string: String = "Hello World"
        var dataBuffer = DataBuffer(string)

        // When
        let readedData = dataBuffer.readData(dataBuffer.readableBytes)

        // Then
        XCTAssertEqual(readedData, Data(string.utf8))
        XCTAssertEqual(dataBuffer.writerIndex, string.count)
        XCTAssertEqual(dataBuffer.readerIndex, string.count)
        XCTAssertEqual(dataBuffer.readableBytes, .zero)
        XCTAssertEqual(dataBuffer.writableBytes, .zero)
    }

    func testDataBuffer_whenInitStaticString_shouldReadContents() async throws {
        // Given
        let string: StaticString = "Hello World"
        var dataBuffer = DataBuffer(string)

        // When
        let readedData = dataBuffer.readData(dataBuffer.readableBytes)

        // Then
        XCTAssertEqual(readedData, "\(string)".data(using: .utf8))
        XCTAssertEqual(dataBuffer.writerIndex, string.utf8CodeUnitCount)
        XCTAssertEqual(dataBuffer.readerIndex, string.utf8CodeUnitCount)
        XCTAssertEqual(dataBuffer.readableBytes, .zero)
        XCTAssertEqual(dataBuffer.writableBytes, .zero)
    }

    func testDataBuffer_whenInitDataBuffer_shouldReadContents() async throws {
        // Given
        let data = Data("Hello World".utf8)
        let dataBuffer = DataBuffer(data)
        var sut1 = DataBuffer(dataBuffer)

        // When
        let readedData = sut1.readData(sut1.readableBytes)

        // Then
        XCTAssertEqual(sut1.writerIndex, dataBuffer.writerIndex)
        XCTAssertEqual(readedData, data)
    }

    func testDataBuffer_whenInitFileURL_shouldBeEmpty() async throws {
        // Given
        let url = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathExtension("FileURL.txt")

        let dataBuffer = DataBuffer(url)

        // When
        let writerIndex = dataBuffer.writerIndex
        let readerIndex = dataBuffer.readerIndex
        let readableBytes = dataBuffer.readableBytes
        let writableBytes = dataBuffer.writableBytes

        // Then
        XCTAssertEqual(writerIndex, .zero)
        XCTAssertEqual(readerIndex, .zero)
        XCTAssertEqual(readableBytes, .zero)
        XCTAssertEqual(writableBytes, .zero)
    }

    func testDataBuffer_whenInitFileBuffer_shouldBeEqual() async throws {
        // Given
        let data = Data.randomData(length: 1_000_000)
        let dataBuffer = DataBuffer(FileBuffer(data))

        // When
        let writerIndex = dataBuffer.writerIndex
        let readerIndex = dataBuffer.readerIndex
        let readableBytes = dataBuffer.readableBytes
        let writableBytes = dataBuffer.writableBytes

        // Then
        XCTAssertEqual(writerIndex, data.count)
        XCTAssertEqual(readerIndex, .zero)
        XCTAssertEqual(readableBytes, data.count)
        XCTAssertEqual(writableBytes, .zero)
    }

    func testDataBuffer_whenReadZeroBytes_shouldBeNil() async throws {
        // Given
        var dataBuffer = DataBuffer()

        // When
        let data = dataBuffer.readData(.zero)

        // Then
        XCTAssertNil(data)
    }
}
