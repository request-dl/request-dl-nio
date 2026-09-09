//
// See LICENSE for this package's licensing information.
//

import NIOCore
import SwiftAsyncTesting
import Testing

@testable import RequestDLInternals
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import struct Foundation.URL
#endif

@Suite(.concurrent(watchdogAffectedPlatformConcurrencyLimit), .nonFatalWatchdog)
struct InternalsDataBufferTests {

    @Test
    func dataBuffer_whenInitURL_shouldBeEmpty() async throws {
        // Given
        let byteURL = Internals.ByteURL()
        let dataBuffer = await Internals.DataBuffer(byteURL)

        // When
        let writerIndex = dataBuffer.writerIndex
        let readerIndex = dataBuffer.readerIndex
        let readableBytes = dataBuffer.readableBytes
        let overwritableBytes = await dataBuffer.overwritableBytes
        let estimatedBytes = await dataBuffer.estimatedBytes

        // Then
        #expect(writerIndex == .zero)
        #expect(readerIndex == .zero)
        #expect(readableBytes == .zero)
        #expect(overwritableBytes == .zero)
        #expect(estimatedBytes == .zero)
    }

    @Test
    func dataBuffer_whenContainsData_shouldWriterBeAtEndAndReaderAtZero() async throws {
        // Given
        let byteURL = Internals.ByteURL()
        let data = Data("Hello world".utf8)
        try data.write(to: byteURL)

        let dataBuffer = await Internals.DataBuffer(byteURL)

        // When
        let writerIndex = dataBuffer.writerIndex
        let readerIndex = dataBuffer.readerIndex
        let readableBytes = dataBuffer.readableBytes
        let overwritableBytes = await dataBuffer.overwritableBytes

        // Then
        #expect(writerIndex == data.count)
        #expect(readerIndex == .zero)
        #expect(readableBytes == data.count)
        #expect(overwritableBytes == .zero)
    }

    @Test
    func dataBuffer_whenContainsData_shouldReadDataAvailable() async throws {
        // Given
        let byteURL = Internals.ByteURL()
        let data = Data("Hello world".utf8)
        try data.write(to: byteURL)

        var dataBuffer = await Internals.DataBuffer(byteURL)

        // When
        let readData = await dataBuffer.readData(data.count)

        // Then
        #expect(dataBuffer.writerIndex == data.count)
        #expect(dataBuffer.readerIndex == data.count)
        #expect(dataBuffer.readableBytes == .zero)
        let overwritableBytes = await dataBuffer.overwritableBytes
        #expect(overwritableBytes == .zero)
        #expect(readData == data)
        let estimatedBytes = await dataBuffer.estimatedBytes
        #expect(estimatedBytes == data.count)
    }

    @Test
    func dataBuffer_whenContainsDataMovingReaderIndex_shouldReadableBytesBeUpdated() async throws {
        // Given
        let byteURL = Internals.ByteURL()
        let data = Data("Hello world".utf8)
        try data.write(to: byteURL)

        let index = 2
        var dataBuffer = await Internals.DataBuffer(byteURL)

        // When
        let readableIndex = dataBuffer.readableBytes
        dataBuffer.moveReaderIndex(to: index)

        // Then
        #expect(readableIndex == data.count)
        #expect(dataBuffer.writerIndex == data.count)
        #expect(dataBuffer.readerIndex == index)
        #expect(dataBuffer.readableBytes == data.count - index)
        let overwritableBytes = await dataBuffer.overwritableBytes
        #expect(overwritableBytes == .zero)
    }

    @Test
    func dataBuffer_whenContainsDataMovingWriterIndex_shouldWritableBytesBeUpdated() async throws {
        // Given
        let byteURL = Internals.ByteURL()
        let data = Data("Hello world".utf8)
        try data.write(to: byteURL)

        let index = data.count - 2
        var dataBuffer = await Internals.DataBuffer(byteURL)

        // When
        let overwritableBytes = await dataBuffer.overwritableBytes
        dataBuffer.moveWriterIndex(to: index)

        // Then
        #expect(overwritableBytes == .zero)
        #expect(dataBuffer.writerIndex == index)
        #expect(dataBuffer.readerIndex == .zero)
        #expect(dataBuffer.readableBytes == index)
        let overwritableBytesAfterMove = await dataBuffer.overwritableBytes
        #expect(overwritableBytesAfterMove == data.count - index)
    }

    @Test
    func dataBuffer_whenWritingWithTwoCopy_shouldWritableBytesBeUpdated() async throws {
        // Given
        let byteURL = Internals.ByteURL()
        let data = Data("Hello World".utf8)
        let sut1 = await Internals.DataBuffer(byteURL)
        var sut2 = sut1

        // When
        let writerIndex = sut1.writerIndex
        let readerIndex = sut1.readerIndex

        await sut2.writeData(data)

        // Then
        #expect(writerIndex == sut1.writerIndex)
        #expect(readerIndex == sut1.readerIndex)
        #expect(sut2.writerIndex == data.count)
        #expect(sut2.readableBytes == data.count)
        let sut1OverwritableBytes = await sut1.overwritableBytes
        #expect(sut1OverwritableBytes == data.count)
        #expect(sut1.readableBytes == .zero)
    }

    @Test
    func dataBuffer_whenWritingWithTwoInstances_shouldWritableBytesBeUpdated() async throws {
        // Given
        let byteURL = Internals.ByteURL()
        let data = Data("Hello World".utf8)
        let sut1 = await Internals.DataBuffer(byteURL)
        var sut2 = await Internals.DataBuffer(byteURL)

        // When
        let writerIndex = sut1.writerIndex
        let readerIndex = sut1.readerIndex

        await sut2.writeData(data)

        // Then
        #expect(writerIndex == sut1.writerIndex)
        #expect(readerIndex == sut1.readerIndex)
        #expect(sut2.writerIndex == data.count)
        #expect(sut2.readableBytes == data.count)
        let sut1OverwritableBytes = await sut1.overwritableBytes
        #expect(sut1OverwritableBytes == data.count)
        #expect(sut1.readableBytes == .zero)
    }

    @Test
    func dataBuffer_whenWritingWithTwoInstancesSimultaneos_shouldWritableBytesBeUpdated() async throws {
        // Given
        let byteURL = Internals.ByteURL()
        let data = Data("Hello World".utf8)
        let writeSliceIndex = 3
        var sut1 = await Internals.DataBuffer(byteURL)
        var sut2 = await Internals.DataBuffer(byteURL)

        // When
        await sut2.writeData(data)
        await sut1.writeData(data[0..<writeSliceIndex])

        // Then
        #expect(sut2.writerIndex == data.count)
        #expect(sut2.readableBytes == data.count)
        let sut1OverwritableBytes = await sut1.overwritableBytes
        #expect(sut1OverwritableBytes == data.count - writeSliceIndex)
        #expect(sut1.readableBytes == writeSliceIndex)
    }

    @Test
    func dataBuffer_whenWritingWithTwoInstancesSimultaneosBytes_shouldWritableBytesBeUpdated() async throws {
        // Given
        let byteURL = Internals.ByteURL()
        let data = Data("Hello World".utf8)
        let writeSliceIndex = 3
        var sut1 = await Internals.DataBuffer(byteURL)
        var sut2 = await Internals.DataBuffer(byteURL)

        // When
        await sut2.writeBytes(data)
        await sut1.writeBytes(data[0..<writeSliceIndex])

        // Then
        #expect(sut2.writerIndex == data.count)
        #expect(sut2.readableBytes == data.count)
        let sut1OverwritableBytes = await sut1.overwritableBytes
        #expect(sut1OverwritableBytes == data.count - writeSliceIndex)
        #expect(sut1.readableBytes == writeSliceIndex)
    }

    @Test
    func dataBuffer_whenReadingWithTwoCopy_shouldReadableBytesBeUpdated() async throws {
        // Given
        let byteURL = Internals.ByteURL()
        let data = Data("Hello World".utf8)
        try data.write(to: byteURL)

        let sut1 = await Internals.DataBuffer(byteURL)
        var sut2 = sut1

        // When
        let writerIndex = sut1.writerIndex
        let readerIndex = sut1.readerIndex

        let readData = await sut2.readData(data.count)

        // Then
        #expect(readData == data)
        #expect(writerIndex == data.count)
        #expect(readerIndex == .zero)
        #expect(sut2.writerIndex == data.count)
        #expect(sut2.readableBytes == .zero)
        let sut1OverwritableBytes = await sut1.overwritableBytes
        #expect(sut1OverwritableBytes == .zero)
        #expect(sut1.readableBytes == data.count)
    }

    @Test
    func dataBuffer_whenReadingWithTwoInstances_shouldReadableBytesBeUpdated() async throws {
        // Given
        let byteURL = Internals.ByteURL()
        let data = Data("Hello World".utf8)
        try data.write(to: byteURL)

        let sut1 = await Internals.DataBuffer(byteURL)
        var sut2 = await Internals.DataBuffer(byteURL)

        // When
        let writerIndex = sut1.writerIndex
        let readerIndex = sut1.readerIndex

        let readData = await sut2.readData(data.count)

        // Then
        #expect(readData == data)
        #expect(writerIndex == data.count)
        #expect(readerIndex == .zero)
        #expect(sut2.writerIndex == data.count)
        #expect(sut2.readableBytes == .zero)
        let sut1OverwritableBytes = await sut1.overwritableBytes
        #expect(sut1OverwritableBytes == .zero)
        #expect(sut1.readableBytes == data.count)
    }

    @Test
    func dataBuffer_whenReadingWithTwoInstancesSimultaneos_shouldReadableBytesBeUpdated() async throws {
        // Given
        let byteURL = Internals.ByteURL()
        let data = Data("Hello World".utf8)
        try data.write(to: byteURL)

        let readSliceIndex = 3
        var sut1 = await Internals.DataBuffer(byteURL)
        var sut2 = await Internals.DataBuffer(byteURL)

        // When
        let readData2 = await sut2.readData(data.count)
        let readData1 = await sut1.readData(readSliceIndex)

        // Then
        #expect(readData1 == data[0..<readSliceIndex])
        #expect(sut1.writerIndex == data.count)
        #expect(sut1.readableBytes == data.count - readSliceIndex)
        let sut1OverwritableBytes = await sut1.overwritableBytes
        #expect(sut1OverwritableBytes == .zero)

        #expect(readData2 == data)
        #expect(sut2.writerIndex == data.count)
        #expect(sut2.readableBytes == .zero)
        let sut2OverwritableBytes = await sut2.overwritableBytes
        #expect(sut2OverwritableBytes == .zero)
    }

    @Test
    func dataBuffer_whenReadingWithTwoInstancesSimultaneosBytes_shouldReadableBytesBeUpdated() async throws {
        // Given
        let byteURL = Internals.ByteURL()
        let data = Data("Hello World".utf8)
        try data.write(to: byteURL)

        let readSliceIndex = 3
        var sut1 = await Internals.DataBuffer(byteURL)
        var sut2 = await Internals.DataBuffer(byteURL)

        // When
        let readBytes2 = await sut2.readBytes(data.count)
        let readBytes1 = await sut1.readBytes(readSliceIndex)

        // Then
        #expect(readBytes1 == Array(data[0..<readSliceIndex]))
        #expect(sut1.writerIndex == data.count)
        #expect(sut1.readableBytes == data.count - readSliceIndex)
        let sut1OverwritableBytes = await sut1.overwritableBytes
        #expect(sut1OverwritableBytes == .zero)

        #expect(readBytes2 == Array(data))
        #expect(sut2.writerIndex == data.count)
        #expect(sut2.readableBytes == .zero)
        let sut2OverwritableBytes = await sut2.overwritableBytes
        #expect(sut2OverwritableBytes == .zero)
    }

    @Test
    func dataBuffer_whenWritingAndReadingSimultaneos_shouldBytesBeUpdatedAndOverrided() async throws {
        // Given
        let byteURL = Internals.ByteURL()
        let data = Data("Hello World".utf8)
        let overrideData = Data("Earth".utf8)

        var sut1 = await Internals.DataBuffer(byteURL)
        var sut2 = await Internals.DataBuffer(byteURL)

        // When
        await sut2.writeData(data)
        let readDataBeforeOverride2 = await sut2.readData(data.count)

        await sut1.writeData(overrideData)
        let readData2 = await sut1.readData(sut1.readableBytes)

        sut2.moveReaderIndex(to: .zero)
        let readDataAfterOverride2 = await sut2.readData(sut2.readableBytes)

        // Then
        #expect(readDataBeforeOverride2 == data)
        #expect(readData2 == overrideData)
        #expect(readDataAfterOverride2 == overrideData + data[overrideData.count..<data.count])

        #expect(sut1.writerIndex == overrideData.count)
        #expect(sut1.readerIndex == overrideData.count)
        let sut1OverwritableBytes = await sut1.overwritableBytes
        #expect(sut1OverwritableBytes == data.count - overrideData.count)
        #expect(sut1.readableBytes == .zero)

        #expect(sut2.writerIndex == data.count)
        #expect(sut2.readerIndex == data.count)
        let sut2OverwritableBytes = await sut2.overwritableBytes
        #expect(sut2OverwritableBytes == .zero)
        #expect(sut2.readableBytes == .zero)
    }

    @Test
    func dataBuffer_whenWritingFromOtherDataBuffer_shouldHaveContentsAppended() async throws {
        // Given
        let byteURL = Internals.ByteURL()
        let otherByteURL = Internals.ByteURL()

        let data = Data("Hello World".utf8)
        let otherData = Data("Earth is a small planet to live".utf8)

        var sut1 = await Internals.DataBuffer(byteURL)
        var sut2 = await Internals.DataBuffer(otherByteURL)

        // When
        await sut1.writeData(data)
        await sut2.writeData(otherData)

        await sut1.writeBuffer(&sut2)

        // Then
        #expect(sut1.writerIndex == data.count + otherData.count)
        #expect(sut2.writerIndex == otherData.count)

        let sut1OverwritableBytes = await sut1.overwritableBytes
        #expect(sut1OverwritableBytes == .zero)
        let sut2OverwritableBytes = await sut2.overwritableBytes
        #expect(sut2OverwritableBytes == .zero)

        #expect(sut1.readerIndex == .zero)
        #expect(sut2.readerIndex == otherData.count)

        let mergedData = await sut1.readData(sut1.readableBytes)
        #expect(mergedData == data + otherData)
    }

    @Test
    func dataBuffer_whenInitEmpty_shouldBeEmpty() async throws {
        // Given
        let dataBuffer = await Internals.DataBuffer()

        // When
        let writerIndex = dataBuffer.writerIndex
        let readerIndex = dataBuffer.readerIndex
        let readableBytes = dataBuffer.readableBytes
        let overwritableBytes = await dataBuffer.overwritableBytes

        // Then
        #expect(writerIndex == .zero)
        #expect(readerIndex == .zero)
        #expect(readableBytes == .zero)
        #expect(overwritableBytes == .zero)
    }

    @Test
    func dataBuffer_whenInitData_shouldReadContents() async throws {
        // Given
        let data = Data("Hello World".utf8)
        var dataBuffer = await Internals.DataBuffer(data)

        // When
        let readData = await dataBuffer.readData(dataBuffer.readableBytes)

        // Then
        #expect(readData == data)
        #expect(dataBuffer.writerIndex == data.count)
        #expect(dataBuffer.readerIndex == data.count)
        #expect(dataBuffer.readableBytes == .zero)
        let overwritableBytes = await dataBuffer.overwritableBytes
        #expect(overwritableBytes == .zero)
    }

    @Test
    func dataBuffer_whenInitBytes_shouldReadContents() async throws {
        // Given
        let bytes = Array(Data("Hello World".utf8))
        var dataBuffer = await Internals.DataBuffer(bytes)

        // When
        let readBytes = await dataBuffer.readBytes(dataBuffer.readableBytes)

        // Then
        #expect(readBytes == bytes)
        #expect(dataBuffer.writerIndex == bytes.count)
        #expect(dataBuffer.readerIndex == bytes.count)
        #expect(dataBuffer.readableBytes == .zero)
        let overwritableBytes = await dataBuffer.overwritableBytes
        #expect(overwritableBytes == .zero)
    }

    @Test
    func dataBuffer_whenInitString_shouldReadContents() async throws {
        // Given
        let string: String = "Hello World"
        var dataBuffer = await Internals.DataBuffer(string)

        // When
        let readData = await dataBuffer.readData(dataBuffer.readableBytes)

        // Then
        #expect(readData == Data(string.utf8))
        #expect(dataBuffer.writerIndex == string.count)
        #expect(dataBuffer.readerIndex == string.count)
        #expect(dataBuffer.readableBytes == .zero)
        let overwritableBytes = await dataBuffer.overwritableBytes
        #expect(overwritableBytes == .zero)
    }

    @Test
    func dataBuffer_whenInitStaticString_shouldReadContents() async throws {
        // Given
        let string: StaticString = "Hello World"
        var dataBuffer = await Internals.DataBuffer(string)

        // When
        let readData = await dataBuffer.readData(dataBuffer.readableBytes)

        // Then
        #expect(readData == "\(string)".data(using: .utf8))
        #expect(dataBuffer.writerIndex == string.utf8CodeUnitCount)
        #expect(dataBuffer.readerIndex == string.utf8CodeUnitCount)
        #expect(dataBuffer.readableBytes == .zero)
        let overwritableBytes = await dataBuffer.overwritableBytes
        #expect(overwritableBytes == .zero)
    }

    @Test
    func dataBuffer_whenInitDataBuffer_shouldReadContents() async throws {
        // Given
        let data = Data("Hello World".utf8)
        let dataBuffer = await Internals.DataBuffer(data)
        var sut1 = await Internals.DataBuffer(dataBuffer)

        // When
        let readData = await sut1.readData(sut1.readableBytes)

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

        let dataBuffer = await Internals.DataBuffer(url)

        // When
        let writerIndex = dataBuffer.writerIndex
        let readerIndex = dataBuffer.readerIndex
        let readableBytes = dataBuffer.readableBytes
        let overwritableBytes = await dataBuffer.overwritableBytes

        // Then
        #expect(writerIndex == .zero)
        #expect(readerIndex == .zero)
        #expect(readableBytes == .zero)
        #expect(overwritableBytes == .zero)
    }

    @Test
    func dataBuffer_whenInitFileBuffer_shouldBeEqual() async throws {
        // Given
        let data = await Data.randomData(length: 1_000_000)
        let dataBuffer = await Internals.DataBuffer(Internals.FileBuffer(data))

        // When
        let writerIndex = dataBuffer.writerIndex
        let readerIndex = dataBuffer.readerIndex
        let readableBytes = dataBuffer.readableBytes
        let overwritableBytes = await dataBuffer.overwritableBytes

        // Then
        #expect(writerIndex == data.count)
        #expect(readerIndex == .zero)
        #expect(readableBytes == data.count)
        #expect(overwritableBytes == .zero)
    }

    @Test
    func dataBuffer_whenReadZeroBytes_shouldBeNil() async throws {
        // Given
        var dataBuffer = await Internals.DataBuffer()

        // When
        let data = await dataBuffer.readData(.zero)

        // Then
        #expect(data == nil)
    }

    @Test
    func dataBuffer_whenReadDataOutOfBounds() async throws {
        // Given
        var dataBuffer = await Internals.DataBuffer(
            Data.randomData(length: 64)
        )

        // When
        let data = await dataBuffer.readData(72)

        // Then
        #expect(data == nil)
    }

    @Test
    func dataBuffer_whenReadBytesOutOfBounds() async throws {
        // Given
        var dataBuffer = await Internals.DataBuffer(
            Data.randomData(length: 64)
        )

        // When
        let bytes = await dataBuffer.readBytes(72)

        // Then
        #expect(bytes == nil)
    }

    @Test
    func dataBuffer_whenInitWithByteURLAlreadySetByteBuffer() async throws {
        // Given
        let data = await Data.randomData(length: 1_024)
        let byteBuffer = ByteBuffer(data: data)
        let byteURL = Internals.ByteURL(byteBuffer)

        // When
        var dataBuffer = await Internals.DataBuffer(byteURL)

        // Then
        #expect(dataBuffer.writerIndex == data.count)
        let readData = await dataBuffer.readData(data.count)
        #expect(readData == data)
    }

    @Test
    func dataBuffer_whenGetData() async throws {
        // Given
        let data = await Data.randomData(length: 1_024)
        let dataBuffer = await Internals.DataBuffer(data)

        // Then
        let retrievedData = await dataBuffer.getData()
        #expect(retrievedData == data)
    }

    @Test
    func dataBuffer_whenGetDataByMovingReaderIndex() async throws {
        // Given
        let data = await Data.randomData(length: 1_024)
        var dataBuffer = await Internals.DataBuffer(data)

        // When
        dataBuffer.moveReaderIndex(to: 64)

        // Then
        let retrievedData = await dataBuffer.getData()
        #expect(retrievedData == data[64..<data.count])
    }

    @Test
    func dataBuffer_whenGetBytes() async throws {
        // Given
        let data = await Data.randomData(length: 1_024)
        let dataBuffer = await Internals.DataBuffer(data)

        // Then
        let retrievedBytes = await dataBuffer.getBytes()
        #expect(retrievedBytes == Array(data))
    }

    @Test
    func dataBuffer_whenGetBytesByMovingReaderIndex() async throws {
        // Given
        let data = await Data.randomData(length: 1_024)
        var dataBuffer = await Internals.DataBuffer(data)

        // When
        dataBuffer.moveReaderIndex(to: 64)

        // Then
        let retrievedBytes = await dataBuffer.getBytes()
        #expect(retrievedBytes == Array(data[64..<data.count]))
    }

    @Test
    func dataBuffer_whenGetBytesAtIndexWithLength() async throws {
        // Given
        let data = await Data.randomData(length: 1_024)
        var dataBuffer = await Internals.DataBuffer(data)

        // When
        dataBuffer.moveReaderIndex(to: 64)

        // Then

        let retrievedBytes = await dataBuffer.getBytes(at: 32, length: 64)
        #expect(retrievedBytes == Array(data[32..<96]))
    }

    @Test
    func dataBuffer_whenGetDataAtIndexWithLength() async throws {
        // Given
        let data = await Data.randomData(length: 1_024)
        var dataBuffer = await Internals.DataBuffer(data)

        // When
        dataBuffer.moveReaderIndex(to: 64)

        // Then
        let retrievedData = await dataBuffer.getData(at: 32, length: 64)
        #expect(retrievedData == data[32..<96])
    }

    @Test
    func dataBuffer_whenSetDataAtWriterIndex() async throws {
        // Given
        let data = await Data.randomData(length: 1_024)
        var dataBuffer = await Internals.DataBuffer(data)

        let writeData = await Data.randomData(length: 64)

        // When
        try await dataBuffer.setData(writeData, at: data.count - 32)

        // Then
        let overwritableBytesAfterWrite = await dataBuffer.overwritableBytes
        #expect(overwritableBytesAfterWrite == writeData.count - 32)

        dataBuffer.moveReaderIndex(to: dataBuffer.writerIndex - 32)
        await dataBuffer.moveWriterIndex(to: dataBuffer.writerIndex + dataBuffer.overwritableBytes)

        let overwrittenData = await dataBuffer.readData(writeData.count)
        #expect(overwrittenData == writeData)
    }

    @Test
    func dataBuffer_whenSetBytesAtWriterIndex() async throws {
        // Given
        let data = await Data.randomData(length: 1_024)
        var dataBuffer = await Internals.DataBuffer(data)

        let writeBytes = await Array(Data.randomData(length: 64))

        // When
        await dataBuffer.setBytes(writeBytes, at: data.count - 32)

        // Then
        let overwritableBytesAfterWrite = await dataBuffer.overwritableBytes
        #expect(overwritableBytesAfterWrite == writeBytes.count - 32)

        dataBuffer.moveReaderIndex(to: dataBuffer.writerIndex - 32)
        await dataBuffer.moveWriterIndex(to: dataBuffer.writerIndex + dataBuffer.overwritableBytes)

        let overwrittenBytes = await dataBuffer.readBytes(writeBytes.count)
        #expect(overwrittenBytes == writeBytes)
    }

    @Test
    func dataBuffer_whenRacingImmutable() async throws {
        // Given
        let dataBuffer = await Internals.DataBuffer(Data.randomData(length: 1_024))

        // When
        let datas = await withTaskGroup(of: Data?.self) { group in
            for index in 0..<1_024 {
                group.addTask {
                    await dataBuffer.getData(at: index, length: 1_024 - index)
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

    @Test
    func dataBuffer_whenInitRealFileURL_shouldReadContentsThroughFileStreamBuffer() async throws {
        // Given
        // `Internals.ByteURL.make(from:)` cannot address a real file `URL` — only an
        // in-memory one — so `init(_ url: URL)` falls back to reading it through a
        // `FileStreamBuffer`-backed `Buffer` and copying the bytes into this one.
        let fileURLManager = try await InternalsFileBufferTests.FileURLManager()
        defer { _ = fileURLManager }

        let fileURL = fileURLManager.url
        let data = Data("Hello world".utf8)
        try data.write(to: fileURL)

        // When
        var dataBuffer = await Internals.DataBuffer(fileURL)
        let readData = await dataBuffer.readData(dataBuffer.readableBytes)

        // Then
        #expect(readData == data)
    }
}
