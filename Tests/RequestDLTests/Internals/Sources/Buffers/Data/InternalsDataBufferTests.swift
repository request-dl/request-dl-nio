/*
 See LICENSE for this package's licensing information.
*/

import XCTest
import NIOCore
@testable import RequestDL

// swiftlint:disable type_body_length file_length
class InternalsDataBufferTests: XCTestCase {

    var byteURL: Internals.ByteURL?

    override func setUp() async throws {
        try await super.setUp()

        byteURL = Internals.ByteURL()
    }

    override func tearDown() async throws {
        try await super.tearDown()

        byteURL = nil
    }

    func testDataBuffer_whenInitURL_shouldBeEmpty() async throws {
        // Given
        let byteURL = try XCTUnwrap(byteURL)
        let dataBuffer = Internals.DataBuffer(byteURL)

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
        let byteURL = try XCTUnwrap(byteURL)
        let data = Data("Hello world".utf8)
        try data.write(to: byteURL)

        let dataBuffer = Internals.DataBuffer(byteURL)

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
        let byteURL = try XCTUnwrap(byteURL)
        let data = Data("Hello world".utf8)
        try data.write(to: byteURL)

        var dataBuffer = Internals.DataBuffer(byteURL)

        // When
        let readData = dataBuffer.readData(data.count)

        // Then
        XCTAssertEqual(dataBuffer.writerIndex, data.count)
        XCTAssertEqual(dataBuffer.readerIndex, data.count)
        XCTAssertEqual(dataBuffer.readableBytes, .zero)
        XCTAssertEqual(dataBuffer.writableBytes, .zero)
        XCTAssertEqual(readData, data)
        XCTAssertEqual(dataBuffer.estimatedBytes, data.count)
    }

    func testDataBuffer_whenContainsDataMovingReaderIndex_shouldReadableBytesBeUpdated() async throws {
        // Given
        let byteURL = try XCTUnwrap(byteURL)
        let data = Data("Hello world".utf8)
        try data.write(to: byteURL)

        let index = 2
        var dataBuffer = Internals.DataBuffer(byteURL)

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
        let byteURL = try XCTUnwrap(byteURL)
        let data = Data("Hello world".utf8)
        try data.write(to: byteURL)

        let index = data.count - 2
        var dataBuffer = Internals.DataBuffer(byteURL)

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
        let byteURL = try XCTUnwrap(byteURL)
        let data = Data("Hello World".utf8)
        let sut1 = Internals.DataBuffer(byteURL)
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
        let byteURL = try XCTUnwrap(byteURL)
        let data = Data("Hello World".utf8)
        let sut1 = Internals.DataBuffer(byteURL)
        var sut2 = Internals.DataBuffer(byteURL)

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
        let byteURL = try XCTUnwrap(byteURL)
        let data = Data("Hello World".utf8)
        let writeSliceIndex = 3
        var sut1 = Internals.DataBuffer(byteURL)
        var sut2 = Internals.DataBuffer(byteURL)

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
        let byteURL = try XCTUnwrap(byteURL)
        let data = Data("Hello World".utf8)
        let writeSliceIndex = 3
        var sut1 = Internals.DataBuffer(byteURL)
        var sut2 = Internals.DataBuffer(byteURL)

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
        let byteURL = try XCTUnwrap(byteURL)
        let data = Data("Hello World".utf8)
        try data.write(to: byteURL)

        let sut1 = Internals.DataBuffer(byteURL)
        var sut2 = sut1

        // When
        let writerIndex = sut1.writerIndex
        let readerIndex = sut1.readerIndex

        let readData = sut2.readData(data.count)

        // Then
        XCTAssertEqual(readData, data)
        XCTAssertEqual(writerIndex, data.count)
        XCTAssertEqual(readerIndex, .zero)
        XCTAssertEqual(sut2.writerIndex, data.count)
        XCTAssertEqual(sut2.readableBytes, .zero)
        XCTAssertEqual(sut1.writableBytes, .zero)
        XCTAssertEqual(sut1.readableBytes, data.count)
    }

    func testDataBuffer_whenReadingWithTwoInstances_shouldReadableBytesBeUpdated() async throws {
        // Given
        let byteURL = try XCTUnwrap(byteURL)
        let data = Data("Hello World".utf8)
        try data.write(to: byteURL)

        let sut1 = Internals.DataBuffer(byteURL)
        var sut2 = Internals.DataBuffer(byteURL)

        // When
        let writerIndex = sut1.writerIndex
        let readerIndex = sut1.readerIndex

        let readData = sut2.readData(data.count)

        // Then
        XCTAssertEqual(readData, data)
        XCTAssertEqual(writerIndex, data.count)
        XCTAssertEqual(readerIndex, .zero)
        XCTAssertEqual(sut2.writerIndex, data.count)
        XCTAssertEqual(sut2.readableBytes, .zero)
        XCTAssertEqual(sut1.writableBytes, .zero)
        XCTAssertEqual(sut1.readableBytes, data.count)
    }

    func testDataBuffer_whenReadingWithTwoInstancesSimultaneos_shouldReadableBytesBeUpdated() async throws {
        // Given
        let byteURL = try XCTUnwrap(byteURL)
        let data = Data("Hello World".utf8)
        try data.write(to: byteURL)

        let readSliceIndex = 3
        var sut1 = Internals.DataBuffer(byteURL)
        var sut2 = Internals.DataBuffer(byteURL)

        // When
        let readData2 = sut2.readData(data.count)
        let readData1 = sut1.readData(readSliceIndex)

        // Then
        XCTAssertEqual(readData1, data[0..<readSliceIndex])
        XCTAssertEqual(sut1.writerIndex, data.count)
        XCTAssertEqual(sut1.readableBytes, data.count - readSliceIndex)
        XCTAssertEqual(sut1.writableBytes, .zero)

        XCTAssertEqual(readData2, data)
        XCTAssertEqual(sut2.writerIndex, data.count)
        XCTAssertEqual(sut2.readableBytes, .zero)
        XCTAssertEqual(sut2.writableBytes, .zero)
    }

    func testDataBuffer_whenReadingWithTwoInstancesSimultaneosBytes_shouldReadableBytesBeUpdated() async throws {
        // Given
        let byteURL = try XCTUnwrap(byteURL)
        let data = Data("Hello World".utf8)
        try data.write(to: byteURL)

        let readSliceIndex = 3
        var sut1 = Internals.DataBuffer(byteURL)
        var sut2 = Internals.DataBuffer(byteURL)

        // When
        let readBytes2 = sut2.readBytes(data.count)
        let readBytes1 = sut1.readBytes(readSliceIndex)

        // Then
        XCTAssertEqual(readBytes1, Array(data[0..<readSliceIndex]))
        XCTAssertEqual(sut1.writerIndex, data.count)
        XCTAssertEqual(sut1.readableBytes, data.count - readSliceIndex)
        XCTAssertEqual(sut1.writableBytes, .zero)

        XCTAssertEqual(readBytes2, Array(data))
        XCTAssertEqual(sut2.writerIndex, data.count)
        XCTAssertEqual(sut2.readableBytes, .zero)
        XCTAssertEqual(sut2.writableBytes, .zero)
    }

    func testDataBuffer_whenWritingAndReadingSimultaneos_shouldBytesBeUpdatedAndOverrided() async throws {
        // Given
        let byteURL = try XCTUnwrap(byteURL)
        let data = Data("Hello World".utf8)
        let overrideData = Data("Earth".utf8)

        var sut1 = Internals.DataBuffer(byteURL)
        var sut2 = Internals.DataBuffer(byteURL)

        // When
        sut2.writeData(data)
        let readDataBeforeOverride2 = sut2.readData(data.count)

        sut1.writeData(overrideData)
        let readData2 = sut1.readData(sut1.readableBytes)

        sut2.moveReaderIndex(to: .zero)
        let readDataAfterOverride2 = sut2.readData(sut2.readableBytes)

        // Then
        XCTAssertEqual(readDataBeforeOverride2, data)
        XCTAssertEqual(readData2, overrideData)
        XCTAssertEqual(readDataAfterOverride2, overrideData + data[overrideData.count..<data.count])

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
        let byteURL = try XCTUnwrap(byteURL)
        let otherByteURL = Internals.ByteURL()

        let data = Data("Hello World".utf8)
        let otherData = Data("Earth is a small planet to live".utf8)

        var sut1 = Internals.DataBuffer(byteURL)
        var sut2 = Internals.DataBuffer(otherByteURL)

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
        let dataBuffer = Internals.DataBuffer()

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
        var dataBuffer = Internals.DataBuffer(data)

        // When
        let readData = dataBuffer.readData(dataBuffer.readableBytes)

        // Then
        XCTAssertEqual(readData, data)
        XCTAssertEqual(dataBuffer.writerIndex, data.count)
        XCTAssertEqual(dataBuffer.readerIndex, data.count)
        XCTAssertEqual(dataBuffer.readableBytes, .zero)
        XCTAssertEqual(dataBuffer.writableBytes, .zero)
    }

    func testDataBuffer_whenInitBytes_shouldReadContents() async throws {
        // Given
        let bytes = Array(Data("Hello World".utf8))
        var dataBuffer = Internals.DataBuffer(bytes)

        // When
        let readBytes = dataBuffer.readBytes(dataBuffer.readableBytes)

        // Then
        XCTAssertEqual(readBytes, bytes)
        XCTAssertEqual(dataBuffer.writerIndex, bytes.count)
        XCTAssertEqual(dataBuffer.readerIndex, bytes.count)
        XCTAssertEqual(dataBuffer.readableBytes, .zero)
        XCTAssertEqual(dataBuffer.writableBytes, .zero)
    }

    func testDataBuffer_whenInitString_shouldReadContents() async throws {
        // Given
        let string: String = "Hello World"
        var dataBuffer = Internals.DataBuffer(string)

        // When
        let readData = dataBuffer.readData(dataBuffer.readableBytes)

        // Then
        XCTAssertEqual(readData, Data(string.utf8))
        XCTAssertEqual(dataBuffer.writerIndex, string.count)
        XCTAssertEqual(dataBuffer.readerIndex, string.count)
        XCTAssertEqual(dataBuffer.readableBytes, .zero)
        XCTAssertEqual(dataBuffer.writableBytes, .zero)
    }

    func testDataBuffer_whenInitStaticString_shouldReadContents() async throws {
        // Given
        let string: StaticString = "Hello World"
        var dataBuffer = Internals.DataBuffer(string)

        // When
        let readData = dataBuffer.readData(dataBuffer.readableBytes)

        // Then
        XCTAssertEqual(readData, "\(string)".data(using: .utf8))
        XCTAssertEqual(dataBuffer.writerIndex, string.utf8CodeUnitCount)
        XCTAssertEqual(dataBuffer.readerIndex, string.utf8CodeUnitCount)
        XCTAssertEqual(dataBuffer.readableBytes, .zero)
        XCTAssertEqual(dataBuffer.writableBytes, .zero)
    }

    func testDataBuffer_whenInitDataBuffer_shouldReadContents() async throws {
        // Given
        let data = Data("Hello World".utf8)
        let dataBuffer = Internals.DataBuffer(data)
        var sut1 = Internals.DataBuffer(dataBuffer)

        // When
        let readData = sut1.readData(sut1.readableBytes)

        // Then
        XCTAssertEqual(sut1.writerIndex, dataBuffer.writerIndex)
        XCTAssertEqual(readData, data)
    }

    func testDataBuffer_whenInitFileURL_shouldBeEmpty() async throws {
        // Given
        let url = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathExtension("FileURL.txt")

        let dataBuffer = Internals.DataBuffer(url)

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
        let dataBuffer = Internals.DataBuffer(Internals.FileBuffer(data))

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
        var dataBuffer = Internals.DataBuffer()

        // When
        let data = dataBuffer.readData(.zero)

        // Then
        XCTAssertNil(data)
    }

    func testDataBuffer_whenReadDataOutOfBounds() async throws {
        // Given
        var dataBuffer = Internals.DataBuffer(
            Data.randomData(length: 64)
        )

        // When
        let data = dataBuffer.readData(72)

        // Then
        XCTAssertNil(data)
    }

    func testDataBuffer_whenReadBytesOutOfBounds() async throws {
        // Given
        var dataBuffer = Internals.DataBuffer(
            Data.randomData(length: 64)
        )

        // When
        let bytes = dataBuffer.readBytes(72)

        // Then
        XCTAssertNil(bytes)
    }

    func testDataBuffer_whenInitWithByteURLAlreadySetByteBuffer() async throws {
        // Given
        let data = Data.randomData(length: 1_024)
        let byteBuffer = ByteBuffer(data: data)
        let byteURL = Internals.ByteURL(byteBuffer)

        // When
        var dataBuffer = Internals.DataBuffer(byteURL)

        // Then
        XCTAssertEqual(dataBuffer.writerIndex, data.count)
        XCTAssertEqual(dataBuffer.readData(data.count), data)
    }

    func testDataBuffer_whenGetData() async throws {
        // Given
        let data = Data.randomData(length: 1_024)
        let dataBuffer = Internals.DataBuffer(data)

        // Then
        XCTAssertEqual(dataBuffer.getData(), data)
    }

    func testDataBuffer_whenGetDataByMovingReaderIndex() async throws {
        // Given
        let data = Data.randomData(length: 1_024)
        var dataBuffer = Internals.DataBuffer(data)

        // When
        dataBuffer.moveReaderIndex(to: 64)

        // Then
        XCTAssertEqual(dataBuffer.getData(), data[64 ..< data.count])
    }

    func testDataBuffer_whenGetBytes() async throws {
        // Given
        let data = Data.randomData(length: 1_024)
        let dataBuffer = Internals.DataBuffer(data)

        // Then
        XCTAssertEqual(dataBuffer.getBytes(), Array(data))
    }

    func testDataBuffer_whenGetBytesByMovingReaderIndex() async throws {
        // Given
        let data = Data.randomData(length: 1_024)
        var dataBuffer = Internals.DataBuffer(data)

        // When
        dataBuffer.moveReaderIndex(to: 64)

        // Then
        XCTAssertEqual(dataBuffer.getBytes(), Array(data[64 ..< data.count]))
    }

    func testDataBuffer_whenGetBytesAtIndexWithLength() async throws {
        // Given
        let data = Data.randomData(length: 1_024)
        var dataBuffer = Internals.DataBuffer(data)

        // When
        dataBuffer.moveReaderIndex(to: 64)

        // Then

        XCTAssertEqual(
            dataBuffer.getBytes(at: 32, length: 64),
            Array(data[32 ..< 96])
        )
    }

    func testDataBuffer_whenGetDataAtIndexWithLength() async throws {
        // Given
        let data = Data.randomData(length: 1_024)
        var dataBuffer = Internals.DataBuffer(data)

        // When
        dataBuffer.moveReaderIndex(to: 64)

        // Then

        XCTAssertEqual(
            dataBuffer.getData(at: 32, length: 64),
            data[32 ..< 96]
        )
    }

    func testDataBuffer_whenSetDataWhenMovingWriterIndex() async throws {
        // Given
        let data = Data.randomData(length: 1_024)
        var dataBuffer = Internals.DataBuffer(data)

        let writeData = Data.randomData(length: 64)

        // When
        dataBuffer.moveWriterIndex(to: data.count - 32)
        dataBuffer.setData(writeData)

        // Then
        XCTAssertEqual(dataBuffer.writableBytes, writeData.count)

        dataBuffer.moveReaderIndex(to: dataBuffer.writerIndex)
        dataBuffer.moveWriterIndex(to: dataBuffer.writerIndex + dataBuffer.writableBytes)

        XCTAssertEqual(
            dataBuffer.readData(writeData.count),
            writeData
        )
    }

    func testDataBuffer_whenSetDataAtWriterIndex() async throws {
        // Given
        let data = Data.randomData(length: 1_024)
        var dataBuffer = Internals.DataBuffer(data)

        let writeData = Data.randomData(length: 64)

        // When
        dataBuffer.setData(writeData, at: data.count - 32)

        // Then
        XCTAssertEqual(dataBuffer.writableBytes, writeData.count - 32)

        dataBuffer.moveReaderIndex(to: dataBuffer.writerIndex - 32)
        dataBuffer.moveWriterIndex(to: dataBuffer.writerIndex + dataBuffer.writableBytes)

        XCTAssertEqual(
            dataBuffer.readData(writeData.count),
            writeData
        )
    }

    func testDataBuffer_whenSetBytesWhenMovingWriterIndex() async throws {
        // Given
        let data = Data.randomData(length: 1_024)
        var dataBuffer = Internals.DataBuffer(data)

        let writeBytes = Array(Data.randomData(length: 64))

        // When
        dataBuffer.moveWriterIndex(to: data.count - 32)
        dataBuffer.setBytes(writeBytes)

        // Then
        XCTAssertEqual(dataBuffer.writableBytes, writeBytes.count)

        dataBuffer.moveReaderIndex(to: dataBuffer.writerIndex)
        dataBuffer.moveWriterIndex(to: dataBuffer.writerIndex + dataBuffer.writableBytes)

        XCTAssertEqual(
            dataBuffer.readBytes(writeBytes.count),
            writeBytes
        )
    }

    func testDataBuffer_whenSetBytesAtWriterIndex() async throws {
        // Given
        let data = Data.randomData(length: 1_024)
        var dataBuffer = Internals.DataBuffer(data)

        let writeBytes = Array(Data.randomData(length: 64))

        // When
        dataBuffer.setBytes(writeBytes, at: data.count - 32)

        // Then
        XCTAssertEqual(dataBuffer.writableBytes, writeBytes.count - 32)

        dataBuffer.moveReaderIndex(to: dataBuffer.writerIndex - 32)
        dataBuffer.moveWriterIndex(to: dataBuffer.writerIndex + dataBuffer.writableBytes)

        XCTAssertEqual(
            dataBuffer.readBytes(writeBytes.count),
            writeBytes
        )
    }

    func testDataBuffer_whenRacingImmutable() async throws {
        // Given
        let dataBuffer = Internals.DataBuffer(Data.randomData(length: 1_024))

        // When
        let datas = await withTaskGroup(of: Data?.self) { group in
            for index in 0 ..< 1_024 {
                group.addTask {
                    return dataBuffer.getData(at: index, length: 1_024 - index)
                }
            }

            var datas = [Data?]()
            for await data in group {
                datas.append(data)
            }
            return datas
        }

        // Then
        XCTAssertEqual(Set(datas.compactMap { $0 }).count, 1_024)
    }
}
// swiftlint:enable type_body_length file_length
