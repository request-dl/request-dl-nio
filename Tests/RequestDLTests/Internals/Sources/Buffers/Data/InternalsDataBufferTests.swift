/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
import NIOCore
@testable import RequestDL

// swiftlint:disable type_body_length file_length
struct InternalsDataBufferTests {

    @Test
    func dataBuffer_whenInitURL_shouldBeEmpty() async throws {
        // Given
        let byteURL = Internals.ByteURL()
        let dataBuffer = Internals.DataBuffer(byteURL)

        // When
        let writerIndex = dataBuffer.writerIndex
        let readerIndex = dataBuffer.readerIndex
        let readableBytes = dataBuffer.readableBytes
        let writableBytes = dataBuffer.writableBytes
        let estimatedBytes = dataBuffer.estimatedBytes

        // Then
        #expect(writerIndex == .zero)
        #expect(readerIndex == .zero)
        #expect(readableBytes == .zero)
        #expect(writableBytes == .zero)
        #expect(estimatedBytes == .zero)
    }

    @Test
    func dataBuffer_whenContainsData_shouldWriterBeAtEndAndReaderAtZero() async throws {
        // Given
        let byteURL = Internals.ByteURL()
        let data = Data("Hello world".utf8)
        try data.write(to: byteURL)

        let dataBuffer = Internals.DataBuffer(byteURL)

        // When
        let writerIndex = dataBuffer.writerIndex
        let readerIndex = dataBuffer.readerIndex
        let readableBytes = dataBuffer.readableBytes
        let writableBytes = dataBuffer.writableBytes

        // Then
        #expect(writerIndex == data.count)
        #expect(readerIndex == .zero)
        #expect(readableBytes == data.count)
        #expect(writableBytes == .zero)
    }

    @Test
    func dataBuffer_whenContainsData_shouldReadDataAvailable() async throws {
        // Given
        let byteURL = Internals.ByteURL()
        let data = Data("Hello world".utf8)
        try data.write(to: byteURL)

        var dataBuffer = Internals.DataBuffer(byteURL)

        // When
        let readData = dataBuffer.readData(data.count)

        // Then
        #expect(dataBuffer.writerIndex == data.count)
        #expect(dataBuffer.readerIndex == data.count)
        #expect(dataBuffer.readableBytes == .zero)
        #expect(dataBuffer.writableBytes == .zero)
        #expect(readData == data)
        #expect(dataBuffer.estimatedBytes == data.count)
    }

    @Test
    func dataBuffer_whenContainsDataMovingReaderIndex_shouldReadableBytesBeUpdated() async throws {
        // Given
        let byteURL = Internals.ByteURL()
        let data = Data("Hello world".utf8)
        try data.write(to: byteURL)

        let index = 2
        var dataBuffer = Internals.DataBuffer(byteURL)

        // When
        let readableIndex = dataBuffer.readableBytes
        dataBuffer.moveReaderIndex(to: index)

        // Then
        #expect(readableIndex == data.count)
        #expect(dataBuffer.writerIndex == data.count)
        #expect(dataBuffer.readerIndex == index)
        #expect(dataBuffer.readableBytes == data.count - index)
        #expect(dataBuffer.writableBytes == .zero)
    }

    @Test
    func dataBuffer_whenContainsDataMovingWriterIndex_shouldWritableBytesBeUpdated() async throws {
        // Given
        let byteURL = Internals.ByteURL()
        let data = Data("Hello world".utf8)
        try data.write(to: byteURL)

        let index = data.count - 2
        var dataBuffer = Internals.DataBuffer(byteURL)

        // When
        let writableBytes = dataBuffer.writableBytes
        dataBuffer.moveWriterIndex(to: index)

        // Then
        #expect(writableBytes == .zero)
        #expect(dataBuffer.writerIndex == index)
        #expect(dataBuffer.readerIndex == .zero)
        #expect(dataBuffer.readableBytes == index)
        #expect(dataBuffer.writableBytes == data.count - index)
    }

    @Test
    func dataBuffer_whenWritingWithTwoCopy_shouldWritableBytesBeUpdated() async throws {
        // Given
        let byteURL = Internals.ByteURL()
        let data = Data("Hello World".utf8)
        let sut1 = Internals.DataBuffer(byteURL)
        var sut2 = sut1

        // When
        let writerIndex = sut1.writerIndex
        let readerIndex = sut1.readerIndex

        sut2.writeData(data)

        // Then
        #expect(writerIndex == sut1.writerIndex)
        #expect(readerIndex == sut1.readerIndex)
        #expect(sut2.writerIndex == data.count)
        #expect(sut2.readableBytes == data.count)
        #expect(sut1.writableBytes == data.count)
        #expect(sut1.readableBytes == .zero)
    }

    @Test
    func dataBuffer_whenWritingWithTwoInstances_shouldWritableBytesBeUpdated() async throws {
        // Given
        let byteURL = Internals.ByteURL()
        let data = Data("Hello World".utf8)
        let sut1 = Internals.DataBuffer(byteURL)
        var sut2 = Internals.DataBuffer(byteURL)

        // When
        let writerIndex = sut1.writerIndex
        let readerIndex = sut1.readerIndex

        sut2.writeData(data)

        // Then
        #expect(writerIndex == sut1.writerIndex)
        #expect(readerIndex == sut1.readerIndex)
        #expect(sut2.writerIndex == data.count)
        #expect(sut2.readableBytes == data.count)
        #expect(sut1.writableBytes == data.count)
        #expect(sut1.readableBytes == .zero)
    }

    @Test
    func dataBuffer_whenWritingWithTwoInstancesSimultaneos_shouldWritableBytesBeUpdated() async throws {
        // Given
        let byteURL = Internals.ByteURL()
        let data = Data("Hello World".utf8)
        let writeSliceIndex = 3
        var sut1 = Internals.DataBuffer(byteURL)
        var sut2 = Internals.DataBuffer(byteURL)

        // When
        sut2.writeData(data)
        sut1.writeData(data[0..<writeSliceIndex])

        // Then
        #expect(sut2.writerIndex == data.count)
        #expect(sut2.readableBytes == data.count)
        #expect(sut1.writableBytes == data.count - writeSliceIndex)
        #expect(sut1.readableBytes == writeSliceIndex)
    }

    @Test
    func dataBuffer_whenWritingWithTwoInstancesSimultaneosBytes_shouldWritableBytesBeUpdated() async throws {
        // Given
        let byteURL = Internals.ByteURL()
        let data = Data("Hello World".utf8)
        let writeSliceIndex = 3
        var sut1 = Internals.DataBuffer(byteURL)
        var sut2 = Internals.DataBuffer(byteURL)

        // When
        sut2.writeBytes(data)
        sut1.writeBytes(data[0..<writeSliceIndex])

        // Then
        #expect(sut2.writerIndex == data.count)
        #expect(sut2.readableBytes == data.count)
        #expect(sut1.writableBytes == data.count - writeSliceIndex)
        #expect(sut1.readableBytes == writeSliceIndex)
    }

    @Test
    func dataBuffer_whenReadingWithTwoCopy_shouldReadableBytesBeUpdated() async throws {
        // Given
        let byteURL = Internals.ByteURL()
        let data = Data("Hello World".utf8)
        try data.write(to: byteURL)

        let sut1 = Internals.DataBuffer(byteURL)
        var sut2 = sut1

        // When
        let writerIndex = sut1.writerIndex
        let readerIndex = sut1.readerIndex

        let readData = sut2.readData(data.count)

        // Then
        #expect(readData == data)
        #expect(writerIndex == data.count)
        #expect(readerIndex == .zero)
        #expect(sut2.writerIndex == data.count)
        #expect(sut2.readableBytes == .zero)
        #expect(sut1.writableBytes == .zero)
        #expect(sut1.readableBytes == data.count)
    }

    @Test
    func dataBuffer_whenReadingWithTwoInstances_shouldReadableBytesBeUpdated() async throws {
        // Given
        let byteURL = Internals.ByteURL()
        let data = Data("Hello World".utf8)
        try data.write(to: byteURL)

        let sut1 = Internals.DataBuffer(byteURL)
        var sut2 = Internals.DataBuffer(byteURL)

        // When
        let writerIndex = sut1.writerIndex
        let readerIndex = sut1.readerIndex

        let readData = sut2.readData(data.count)

        // Then
        #expect(readData == data)
        #expect(writerIndex == data.count)
        #expect(readerIndex == .zero)
        #expect(sut2.writerIndex == data.count)
        #expect(sut2.readableBytes == .zero)
        #expect(sut1.writableBytes == .zero)
        #expect(sut1.readableBytes == data.count)
    }

    @Test
    func dataBuffer_whenReadingWithTwoInstancesSimultaneos_shouldReadableBytesBeUpdated() async throws {
        // Given
        let byteURL = Internals.ByteURL()
        let data = Data("Hello World".utf8)
        try data.write(to: byteURL)

        let readSliceIndex = 3
        var sut1 = Internals.DataBuffer(byteURL)
        var sut2 = Internals.DataBuffer(byteURL)

        // When
        let readData2 = sut2.readData(data.count)
        let readData1 = sut1.readData(readSliceIndex)

        // Then
        #expect(readData1 == data[0..<readSliceIndex])
        #expect(sut1.writerIndex == data.count)
        #expect(sut1.readableBytes == data.count - readSliceIndex)
        #expect(sut1.writableBytes == .zero)

        #expect(readData2 == data)
        #expect(sut2.writerIndex == data.count)
        #expect(sut2.readableBytes == .zero)
        #expect(sut2.writableBytes == .zero)
    }

    @Test
    func dataBuffer_whenReadingWithTwoInstancesSimultaneosBytes_shouldReadableBytesBeUpdated() async throws {
        // Given
        let byteURL = Internals.ByteURL()
        let data = Data("Hello World".utf8)
        try data.write(to: byteURL)

        let readSliceIndex = 3
        var sut1 = Internals.DataBuffer(byteURL)
        var sut2 = Internals.DataBuffer(byteURL)

        // When
        let readBytes2 = sut2.readBytes(data.count)
        let readBytes1 = sut1.readBytes(readSliceIndex)

        // Then
        #expect(readBytes1 == Array(data[0..<readSliceIndex]))
        #expect(sut1.writerIndex == data.count)
        #expect(sut1.readableBytes == data.count - readSliceIndex)
        #expect(sut1.writableBytes == .zero)

        #expect(readBytes2 == Array(data))
        #expect(sut2.writerIndex == data.count)
        #expect(sut2.readableBytes == .zero)
        #expect(sut2.writableBytes == .zero)
    }

    @Test
    func dataBuffer_whenWritingAndReadingSimultaneos_shouldBytesBeUpdatedAndOverrided() async throws {
        // Given
        let byteURL = Internals.ByteURL()
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
        #expect(readDataBeforeOverride2 == data)
        #expect(readData2 == overrideData)
        #expect(readDataAfterOverride2 == overrideData + data[overrideData.count..<data.count])

        #expect(sut1.writerIndex == overrideData.count)
        #expect(sut1.readerIndex == overrideData.count)
        #expect(sut1.writableBytes == data.count - overrideData.count)
        #expect(sut1.readableBytes == .zero)

        #expect(sut2.writerIndex == data.count)
        #expect(sut2.readerIndex == data.count)
        #expect(sut2.writableBytes == .zero)
        #expect(sut2.readableBytes == .zero)
    }

    @Test
    func dataBuffer_whenWritingFromOtherDataBuffer_shouldHaveContentsAppended() async throws {
        // Given
        let byteURL = Internals.ByteURL()
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
        #expect(sut1.writerIndex == data.count + otherData.count)
        #expect(sut2.writerIndex == otherData.count)

        #expect(sut1.writableBytes == .zero)
        #expect(sut2.writableBytes == .zero)

        #expect(sut1.readerIndex == .zero)
        #expect(sut2.readerIndex == otherData.count)

        #expect(sut1.readData(sut1.readableBytes) == data + otherData)
    }

    @Test
    func dataBuffer_whenInitEmpty_shouldBeEmpty() async throws {
        // Given
        let dataBuffer = Internals.DataBuffer()

        // When
        let writerIndex = dataBuffer.writerIndex
        let readerIndex = dataBuffer.readerIndex
        let readableBytes = dataBuffer.readableBytes
        let writableBytes = dataBuffer.writableBytes

        // Then
        #expect(writerIndex == .zero)
        #expect(readerIndex == .zero)
        #expect(readableBytes == .zero)
        #expect(writableBytes == .zero)
    }

    @Test
    func dataBuffer_whenInitData_shouldReadContents() async throws {
        // Given
        let data = Data("Hello World".utf8)
        var dataBuffer = Internals.DataBuffer(data)

        // When
        let readData = dataBuffer.readData(dataBuffer.readableBytes)

        // Then
        #expect(readData == data)
        #expect(dataBuffer.writerIndex == data.count)
        #expect(dataBuffer.readerIndex == data.count)
        #expect(dataBuffer.readableBytes == .zero)
        #expect(dataBuffer.writableBytes == .zero)
    }

    @Test
    func dataBuffer_whenInitBytes_shouldReadContents() async throws {
        // Given
        let bytes = Array(Data("Hello World".utf8))
        var dataBuffer = Internals.DataBuffer(bytes)

        // When
        let readBytes = dataBuffer.readBytes(dataBuffer.readableBytes)

        // Then
        #expect(readBytes == bytes)
        #expect(dataBuffer.writerIndex == bytes.count)
        #expect(dataBuffer.readerIndex == bytes.count)
        #expect(dataBuffer.readableBytes == .zero)
        #expect(dataBuffer.writableBytes == .zero)
    }

    @Test
    func dataBuffer_whenInitString_shouldReadContents() async throws {
        // Given
        let string: String = "Hello World"
        var dataBuffer = Internals.DataBuffer(string)

        // When
        let readData = dataBuffer.readData(dataBuffer.readableBytes)

        // Then
        #expect(readData == Data(string.utf8))
        #expect(dataBuffer.writerIndex == string.count)
        #expect(dataBuffer.readerIndex == string.count)
        #expect(dataBuffer.readableBytes == .zero)
        #expect(dataBuffer.writableBytes == .zero)
    }

    @Test
    func dataBuffer_whenInitStaticString_shouldReadContents() async throws {
        // Given
        let string: StaticString = "Hello World"
        var dataBuffer = Internals.DataBuffer(string)

        // When
        let readData = dataBuffer.readData(dataBuffer.readableBytes)

        // Then
        #expect(readData == "\(string)".data(using: .utf8))
        #expect(dataBuffer.writerIndex == string.utf8CodeUnitCount)
        #expect(dataBuffer.readerIndex == string.utf8CodeUnitCount)
        #expect(dataBuffer.readableBytes == .zero)
        #expect(dataBuffer.writableBytes == .zero)
    }

    @Test
    func dataBuffer_whenInitDataBuffer_shouldReadContents() async throws {
        // Given
        let data = Data("Hello World".utf8)
        let dataBuffer = Internals.DataBuffer(data)
        var sut1 = Internals.DataBuffer(dataBuffer)

        // When
        let readData = sut1.readData(sut1.readableBytes)

        // Then
        #expect(sut1.writerIndex == dataBuffer.writerIndex)
        #expect(readData == data)
    }

    @Test
    func dataBuffer_whenInitFileURL_shouldBeEmpty() async throws {
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
        #expect(writerIndex == .zero)
        #expect(readerIndex == .zero)
        #expect(readableBytes == .zero)
        #expect(writableBytes == .zero)
    }

    @Test
    func dataBuffer_whenInitFileBuffer_shouldBeEqual() async throws {
        // Given
        let data = Data.randomData(length: 1_000_000)
        let dataBuffer = Internals.DataBuffer(Internals.FileBuffer(data))

        // When
        let writerIndex = dataBuffer.writerIndex
        let readerIndex = dataBuffer.readerIndex
        let readableBytes = dataBuffer.readableBytes
        let writableBytes = dataBuffer.writableBytes

        // Then
        #expect(writerIndex == data.count)
        #expect(readerIndex == .zero)
        #expect(readableBytes == data.count)
        #expect(writableBytes == .zero)
    }

    @Test
    func dataBuffer_whenReadZeroBytes_shouldBeNil() async throws {
        // Given
        var dataBuffer = Internals.DataBuffer()

        // When
        let data = dataBuffer.readData(.zero)

        // Then
        #expect(data == nil)
    }

    @Test
    func dataBuffer_whenReadDataOutOfBounds() async throws {
        // Given
        var dataBuffer = Internals.DataBuffer(
            Data.randomData(length: 64)
        )

        // When
        let data = dataBuffer.readData(72)

        // Then
        #expect(data == nil)
    }

    @Test
    func dataBuffer_whenReadBytesOutOfBounds() async throws {
        // Given
        var dataBuffer = Internals.DataBuffer(
            Data.randomData(length: 64)
        )

        // When
        let bytes = dataBuffer.readBytes(72)

        // Then
        #expect(bytes == nil)
    }

    @Test
    func dataBuffer_whenInitWithByteURLAlreadySetByteBuffer() async throws {
        // Given
        let data = Data.randomData(length: 1_024)
        let byteBuffer = ByteBuffer(data: data)
        let byteURL = Internals.ByteURL(byteBuffer)

        // When
        var dataBuffer = Internals.DataBuffer(byteURL)

        // Then
        #expect(dataBuffer.writerIndex == data.count)
        #expect(dataBuffer.readData(data.count) == data)
    }

    @Test
    func dataBuffer_whenGetData() async throws {
        // Given
        let data = Data.randomData(length: 1_024)
        let dataBuffer = Internals.DataBuffer(data)

        // Then
        #expect(dataBuffer.getData() == data)
    }

    @Test
    func dataBuffer_whenGetDataByMovingReaderIndex() async throws {
        // Given
        let data = Data.randomData(length: 1_024)
        var dataBuffer = Internals.DataBuffer(data)

        // When
        dataBuffer.moveReaderIndex(to: 64)

        // Then
        #expect(dataBuffer.getData() == data[64 ..< data.count])
    }

    @Test
    func dataBuffer_whenGetBytes() async throws {
        // Given
        let data = Data.randomData(length: 1_024)
        let dataBuffer = Internals.DataBuffer(data)

        // Then
        #expect(dataBuffer.getBytes() == Array(data))
    }

    @Test
    func dataBuffer_whenGetBytesByMovingReaderIndex() async throws {
        // Given
        let data = Data.randomData(length: 1_024)
        var dataBuffer = Internals.DataBuffer(data)

        // When
        dataBuffer.moveReaderIndex(to: 64)

        // Then
        #expect(dataBuffer.getBytes() == Array(data[64 ..< data.count]))
    }

    @Test
    func dataBuffer_whenGetBytesAtIndexWithLength() async throws {
        // Given
        let data = Data.randomData(length: 1_024)
        var dataBuffer = Internals.DataBuffer(data)

        // When
        dataBuffer.moveReaderIndex(to: 64)

        // Then

        #expect(dataBuffer.getBytes(at: 32, length: 64) == Array(data[32 ..< 96]))
    }

    @Test
    func dataBuffer_whenGetDataAtIndexWithLength() async throws {
        // Given
        let data = Data.randomData(length: 1_024)
        var dataBuffer = Internals.DataBuffer(data)

        // When
        dataBuffer.moveReaderIndex(to: 64)

        // Then

        #expect(dataBuffer.getData(at: 32, length: 64) == data[32 ..< 96])
    }

    @Test
    func dataBuffer_whenSetDataWhenMovingWriterIndex() async throws {
        // Given
        let data = Data.randomData(length: 1_024)
        var dataBuffer = Internals.DataBuffer(data)

        let writeData = Data.randomData(length: 64)

        // When
        dataBuffer.moveWriterIndex(to: data.count - 32)
        dataBuffer.setData(writeData)

        // Then
        #expect(dataBuffer.writableBytes == writeData.count)

        dataBuffer.moveReaderIndex(to: dataBuffer.writerIndex)
        dataBuffer.moveWriterIndex(to: dataBuffer.writerIndex + dataBuffer.writableBytes)

        #expect(dataBuffer.readData(writeData.count) == writeData)
    }

    @Test
    func dataBuffer_whenSetDataAtWriterIndex() async throws {
        // Given
        let data = Data.randomData(length: 1_024)
        var dataBuffer = Internals.DataBuffer(data)

        let writeData = Data.randomData(length: 64)

        // When
        dataBuffer.setData(writeData, at: data.count - 32)

        // Then
        #expect(dataBuffer.writableBytes == writeData.count - 32)

        dataBuffer.moveReaderIndex(to: dataBuffer.writerIndex - 32)
        dataBuffer.moveWriterIndex(to: dataBuffer.writerIndex + dataBuffer.writableBytes)

        #expect(dataBuffer.readData(writeData.count) == writeData)
    }

    @Test
    func dataBuffer_whenSetBytesWhenMovingWriterIndex() async throws {
        // Given
        let data = Data.randomData(length: 1_024)
        var dataBuffer = Internals.DataBuffer(data)

        let writeBytes = Array(Data.randomData(length: 64))

        // When
        dataBuffer.moveWriterIndex(to: data.count - 32)
        dataBuffer.setBytes(writeBytes)

        // Then
        #expect(dataBuffer.writableBytes == writeBytes.count)

        dataBuffer.moveReaderIndex(to: dataBuffer.writerIndex)
        dataBuffer.moveWriterIndex(to: dataBuffer.writerIndex + dataBuffer.writableBytes)

        #expect(dataBuffer.readBytes(writeBytes.count) == writeBytes)
    }

    @Test
    func dataBuffer_whenSetBytesAtWriterIndex() async throws {
        // Given
        let data = Data.randomData(length: 1_024)
        var dataBuffer = Internals.DataBuffer(data)

        let writeBytes = Array(Data.randomData(length: 64))

        // When
        dataBuffer.setBytes(writeBytes, at: data.count - 32)

        // Then
        #expect(dataBuffer.writableBytes == writeBytes.count - 32)

        dataBuffer.moveReaderIndex(to: dataBuffer.writerIndex - 32)
        dataBuffer.moveWriterIndex(to: dataBuffer.writerIndex + dataBuffer.writableBytes)

        #expect(dataBuffer.readBytes(writeBytes.count) == writeBytes)
    }

    @Test
    func dataBuffer_whenRacingImmutable() async throws {
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
        #expect(Set(datas.compactMap { $0 }).count == 1_024)
    }
}
// swiftlint:enable type_body_length file_length
