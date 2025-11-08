/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

// swiftlint:disable type_body_length file_length
struct InternalsFileBufferTests {

    final class FileURLManager: Sendable {

        let url: URL

        init() throws {
            url = URL(fileURLWithPath: #file + ".\(UUID().uuidString)")
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("FileBufferTests.txt")

            try url.removeIfNeeded()
        }

        deinit {
            try? url.removeIfNeeded()
        }
    }

    @Test
    func fileBuffer_whenInitURL_shouldBeEmpty() async throws {
        // Given
        let fileURLManager = try FileURLManager()
        let fileURL = fileURLManager.url
        let fileBuffer = Internals.FileBuffer(fileURL)

        // When
        let writerIndex = fileBuffer.writerIndex
        let readerIndex = fileBuffer.readerIndex
        let readableBytes = fileBuffer.readableBytes
        let writableBytes = fileBuffer.writableBytes
        let estimatedBytes = fileBuffer.estimatedBytes

        // Then
        #expect(writerIndex == .zero)
        #expect(readerIndex == .zero)
        #expect(readableBytes == .zero)
        #expect(writableBytes == .zero)
        #expect(estimatedBytes == .zero)
    }

    @Test
    func fileBuffer_whenContainsData_shouldWriterBeAtEndAndReaderAtZero() async throws {
        // Given
        let fileURLManager = try FileURLManager()
        let fileURL = fileURLManager.url
        let data = Data("Hello world".utf8)
        try data.write(to: fileURL)

        let fileBuffer = Internals.FileBuffer(fileURL)

        // When
        let writerIndex = fileBuffer.writerIndex
        let readerIndex = fileBuffer.readerIndex
        let readableBytes = fileBuffer.readableBytes
        let writableBytes = fileBuffer.writableBytes

        // Then
        #expect(writerIndex == data.count)
        #expect(readerIndex == .zero)
        #expect(readableBytes == data.count)
        #expect(writableBytes == .zero)
    }

    @Test
    func fileBuffer_whenContainsData_shouldReadDataAvailable() async throws {
        // Given
        let fileURLManager = try FileURLManager()
        let fileURL = fileURLManager.url
        let data = Data("Hello world".utf8)
        try data.write(to: fileURL)

        var fileBuffer = Internals.FileBuffer(fileURL)

        // When
        let readData = fileBuffer.readData(data.count)

        // Then
        #expect(fileBuffer.writerIndex == data.count)
        #expect(fileBuffer.readerIndex == data.count)
        #expect(fileBuffer.readableBytes == .zero)
        #expect(fileBuffer.writableBytes == .zero)
        #expect(readData == data)
        #expect(fileBuffer.estimatedBytes == data.count)
    }

    @Test
    func fileBuffer_whenContainsDataMovingReaderIndex_shouldReadableBytesBeUpdated() async throws {
        // Given
        let fileURLManager = try FileURLManager()
        let fileURL = fileURLManager.url
        let data = Data("Hello world".utf8)
        try data.write(to: fileURL)

        let index = 2
        var fileBuffer = Internals.FileBuffer(fileURL)

        // When
        let readableIndex = fileBuffer.readableBytes
        fileBuffer.moveReaderIndex(to: index)

        // Then
        #expect(readableIndex == data.count)
        #expect(fileBuffer.writerIndex == data.count)
        #expect(fileBuffer.readerIndex == index)
        #expect(fileBuffer.readableBytes == data.count - index)
        #expect(fileBuffer.writableBytes == .zero)
    }

    @Test
    func fileBuffer_whenContainsDataMovingWriterIndex_shouldWritableBytesBeUpdated() async throws {
        // Given
        let fileURLManager = try FileURLManager()
        let fileURL = fileURLManager.url
        let data = Data("Hello world".utf8)
        try data.write(to: fileURL)

        let index = data.count - 2
        var fileBuffer = Internals.FileBuffer(fileURL)

        // When
        let writableBytes = fileBuffer.writableBytes
        fileBuffer.moveWriterIndex(to: index)

        // Then
        #expect(writableBytes == .zero)
        #expect(fileBuffer.writerIndex == index)
        #expect(fileBuffer.readerIndex == .zero)
        #expect(fileBuffer.readableBytes == index)
        #expect(fileBuffer.writableBytes == data.count - index)
    }

    @Test
    func fileBuffer_whenWritingWithTwoCopy_shouldWritableBytesBeUpdated() async throws {
        // Given
        let fileURLManager = try FileURLManager()
        let fileURL = fileURLManager.url
        let data = Data("Hello World".utf8)
        let sut1 = Internals.FileBuffer(fileURL)
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
    func fileBuffer_whenWritingWithTwoInstances_shouldWritableBytesBeUpdated() async throws {
        // Given
        let fileURLManager = try FileURLManager()
        let fileURL = fileURLManager.url
        let data = Data("Hello World".utf8)
        let sut1 = Internals.FileBuffer(fileURL)
        var sut2 = Internals.FileBuffer(fileURL)

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
    func fileBuffer_whenWritingWithTwoInstancesSimultaneos_shouldWritableBytesBeUpdated() async throws {
        // Given
        let fileURLManager = try FileURLManager()
        let fileURL = fileURLManager.url
        let data = Data("Hello World".utf8)
        let writeSliceIndex = 3
        var sut1 = Internals.FileBuffer(fileURL)
        var sut2 = Internals.FileBuffer(fileURL)

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
    func fileBuffer_whenWritingWithTwoInstancesSimultaneosBytes_shouldWritableBytesBeUpdated() async throws {
        // Given
        let fileURLManager = try FileURLManager()
        let fileURL = fileURLManager.url
        let data = Data("Hello World".utf8)
        let writeSliceIndex = 3
        var sut1 = Internals.FileBuffer(fileURL)
        var sut2 = Internals.FileBuffer(fileURL)

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
    func fileBuffer_whenReadingWithTwoCopy_shouldReadableBytesBeUpdated() async throws {
        // Given
        let fileURLManager = try FileURLManager()
        let fileURL = fileURLManager.url
        let data = Data("Hello World".utf8)
        try data.write(to: fileURL)

        let sut1 = Internals.FileBuffer(fileURL)
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
    func fileBuffer_whenReadingWithTwoInstances_shouldReadableBytesBeUpdated() async throws {
        // Given
        let fileURLManager = try FileURLManager()
        let fileURL = fileURLManager.url
        let data = Data("Hello World".utf8)
        try data.write(to: fileURL)

        let sut1 = Internals.FileBuffer(fileURL)
        var sut2 = Internals.FileBuffer(fileURL)

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
    func fileBuffer_whenReadingWithTwoInstancesSimultaneos_shouldReadableBytesBeUpdated() async throws {
        // Given
        let fileURLManager = try FileURLManager()
        let fileURL = fileURLManager.url
        let data = Data("Hello World".utf8)
        try data.write(to: fileURL)

        let readSliceIndex = 3
        var sut1 = Internals.FileBuffer(fileURL)
        var sut2 = Internals.FileBuffer(fileURL)

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
    func fileBuffer_whenReadingWithTwoInstancesSimultaneosBytes_shouldReadableBytesBeUpdated() async throws {
        // Given
        let fileURLManager = try FileURLManager()
        let fileURL = fileURLManager.url
        let data = Data("Hello World".utf8)
        try data.write(to: fileURL)

        let readSliceIndex = 3
        var sut1 = Internals.FileBuffer(fileURL)
        var sut2 = Internals.FileBuffer(fileURL)

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
    func fileBuffer_whenWritingAndReadingSimultaneos_shouldBytesBeUpdatedAndOverrided() async throws {
        // Given
        let fileURLManager = try FileURLManager()
        let fileURL = fileURLManager.url
        let data = Data("Hello World".utf8)
        let overrideData = Data("Earth".utf8)

        var sut1 = Internals.FileBuffer(fileURL)
        var sut2 = Internals.FileBuffer(fileURL)

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
    func fileBuffer_whenWritingFromOtherFileBuffer_shouldHaveContentsAppended() async throws {
        // Given
        let fileURLManager = try FileURLManager()
        let fileURL = fileURLManager.url
        let otherFile = fileURL
            .deletingLastPathComponent()
            .appendingPathComponent("FileBufferOtherFile.txt")

        defer { try? otherFile.removeIfNeeded() }

        let data = Data("Hello World".utf8)
        let otherData = Data("Earth is a small planet to live".utf8)

        var sut1 = Internals.FileBuffer(fileURL)
        var sut2 = Internals.FileBuffer(otherFile)

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
    func fileBuffer_whenInitEmpty_shouldBeEmpty() async throws {
        // Given
        let fileBuffer = Internals.FileBuffer()

        // When
        let writerIndex = fileBuffer.writerIndex
        let readerIndex = fileBuffer.readerIndex
        let readableBytes = fileBuffer.readableBytes
        let writableBytes = fileBuffer.writableBytes

        // Then
        #expect(writerIndex == .zero)
        #expect(readerIndex == .zero)
        #expect(readableBytes == .zero)
        #expect(writableBytes == .zero)
    }

    @Test
    func fileBuffer_whenInitData_shouldReadContents() async throws {
        // Given
        let data = Data("Hello World".utf8)
        var fileBuffer = Internals.FileBuffer(data)

        // When
        let readData = fileBuffer.readData(fileBuffer.readableBytes)

        // Then
        #expect(readData == data)
        #expect(fileBuffer.writerIndex == data.count)
        #expect(fileBuffer.readerIndex == data.count)
        #expect(fileBuffer.readableBytes == .zero)
        #expect(fileBuffer.writableBytes == .zero)
    }

    @Test
    func fileBuffer_whenInitBytes_shouldReadContents() async throws {
        // Given
        let data = Data("Hello World".utf8)
        let bytes = Array(data)
        var fileBuffer = Internals.FileBuffer(BytesSequence(data))

        // When
        let readBytes = fileBuffer.readBytes(fileBuffer.readableBytes)

        // Then
        #expect(readBytes == bytes)
        #expect(fileBuffer.writerIndex == bytes.count)
        #expect(fileBuffer.readerIndex == bytes.count)
        #expect(fileBuffer.readableBytes == .zero)
        #expect(fileBuffer.writableBytes == .zero)
    }

    @Test
    func fileBuffer_whenInitString_shouldReadContents() async throws {
        // Given
        let string: String = "Hello World"
        var fileBuffer = Internals.FileBuffer(string)

        // When
        let readData = fileBuffer.readData(fileBuffer.readableBytes)

        // Then
        #expect(readData == Data(string.utf8))
        #expect(fileBuffer.writerIndex == string.count)
        #expect(fileBuffer.readerIndex == string.count)
        #expect(fileBuffer.readableBytes == .zero)
        #expect(fileBuffer.writableBytes == .zero)
    }

    @Test
    func fileBuffer_whenInitStaticString_shouldReadContents() async throws {
        // Given
        let string: StaticString = "Hello World"
        var fileBuffer = Internals.FileBuffer(string)

        // When
        let readData = fileBuffer.readData(fileBuffer.readableBytes)

        // Then
        #expect(readData == "\(string)".data(using: .utf8))
        #expect(fileBuffer.writerIndex == string.utf8CodeUnitCount)
        #expect(fileBuffer.readerIndex == string.utf8CodeUnitCount)
        #expect(fileBuffer.readableBytes == .zero)
        #expect(fileBuffer.writableBytes == .zero)
    }

    @Test
    func fileBuffer_whenInitFileBuffer_shouldReadContents() async throws {
        // Given
        let data = Data("Hello World".utf8)
        let fileBuffer = Internals.FileBuffer(data)
        var sut1 = Internals.FileBuffer(fileBuffer)

        // When
        let readData = sut1.readData(sut1.readableBytes)

        // Then
        #expect(sut1.writerIndex == fileBuffer.writerIndex)
        #expect(readData == data)
    }

    @Test
    func fileBuffer_whenInitByteURL_shouldBeEmpty() async throws {
        // Given
        let url = Internals.ByteURL()

        let fileBuffer = Internals.FileBuffer(url)

        // When
        let writerIndex = fileBuffer.writerIndex
        let readerIndex = fileBuffer.readerIndex
        let readableBytes = fileBuffer.readableBytes
        let writableBytes = fileBuffer.writableBytes

        // Then
        #expect(writerIndex == .zero)
        #expect(readerIndex == .zero)
        #expect(readableBytes == .zero)
        #expect(writableBytes == .zero)
    }

    @Test
    func fileBuffer_whenInitDataBuffer_shouldBeEqual() async throws {
        // Given
        let data = Data.randomData(length: 1_000_000)
        let fileBuffer = Internals.FileBuffer(Internals.DataBuffer(data))

        // When
        let writerIndex = fileBuffer.writerIndex
        let readerIndex = fileBuffer.readerIndex
        let readableBytes = fileBuffer.readableBytes
        let writableBytes = fileBuffer.writableBytes

        // Then
        #expect(writerIndex == data.count)
        #expect(readerIndex == .zero)
        #expect(readableBytes == data.count)
        #expect(writableBytes == .zero)
    }

    @Test
    func fileBuffer_whenReadZeroBytes_shouldBeNil() async throws {
        // Given
        var dataBuffer = Internals.FileBuffer()

        // When
        let data = dataBuffer.readData(.zero)

        // Then
        #expect(data == nil)
    }

    @Test
    func fileBuffer_whenReadDataOutOfBounds() async throws {
        // Given
        var fileBuffer = Internals.FileBuffer(
            Data.randomData(length: 64)
        )

        // When
        let data = fileBuffer.readData(72)

        // Then
        #expect(data == nil)
    }

    @Test
    func fileBuffer_whenReadBytesOutOfBounds() async throws {
        // Given
        var fileBuffer = Internals.FileBuffer(
            Data.randomData(length: 64)
        )

        // When
        let bytes = fileBuffer.readBytes(72)

        // Then
        #expect(bytes == nil)
    }

    @Test
    func fileBuffer_whenGetData() async throws {
        // Given
        let data = Data.randomData(length: 1_024)
        let fileBuffer = Internals.FileBuffer(data)

        // Then
        #expect(fileBuffer.getData() == data)
    }

    @Test
    func fileBuffer_whenGetDataByMovingReaderIndex() async throws {
        // Given
        let data = Data.randomData(length: 1_024)
        var fileBuffer = Internals.FileBuffer(data)

        // When
        fileBuffer.moveReaderIndex(to: 64)

        // Then
        #expect(fileBuffer.getData() == data[64 ..< data.count])
    }

    @Test
    func fileBuffer_whenGetBytes() async throws {
        // Given
        let data = Data.randomData(length: 1_024)
        let fileBuffer = Internals.FileBuffer(data)

        // Then
        #expect(fileBuffer.getBytes() == Array(data))
    }

    @Test
    func fileBuffer_whenGetBytesByMovingReaderIndex() async throws {
        // Given
        let data = Data.randomData(length: 1_024)
        var fileBuffer = Internals.FileBuffer(data)

        // When
        fileBuffer.moveReaderIndex(to: 64)

        // Then
        #expect(fileBuffer.getBytes() == Array(data[64 ..< data.count]))
    }

    @Test
    func fileBuffer_whenGetBytesAtIndexWithLength() async throws {
        // Given
        let data = Data.randomData(length: 1_024)
        var fileBuffer = Internals.FileBuffer(data)

        // When
        fileBuffer.moveReaderIndex(to: 64)

        // Then

        #expect(fileBuffer.getBytes(at: 32, length: 64) == Array(data[32 ..< 96]))
    }

    @Test
    func fileBuffer_whenGetDataAtIndexWithLength() async throws {
        // Given
        let data = Data.randomData(length: 1_024)
        var fileBuffer = Internals.FileBuffer(data)

        // When
        fileBuffer.moveReaderIndex(to: 64)

        // Then

        #expect(fileBuffer.getData(at: 32, length: 64) == data[32 ..< 96])
    }

    @Test
    func fileBuffer_whenSetDataWhenMovingWriterIndex() async throws {
        // Given
        let data = Data.randomData(length: 1_024)
        var fileBuffer = Internals.FileBuffer(data)

        let writeData = Data.randomData(length: 64)

        // When
        fileBuffer.moveWriterIndex(to: data.count - 32)
        fileBuffer.setData(writeData)

        // Then
        #expect(fileBuffer.writableBytes == writeData.count)

        fileBuffer.moveReaderIndex(to: fileBuffer.writerIndex)
        fileBuffer.moveWriterIndex(to: fileBuffer.writerIndex + fileBuffer.writableBytes)

        #expect(fileBuffer.readData(writeData.count) == writeData)
    }

    @Test
    func fileBuffer_whenSetDataAtWriterIndex() async throws {
        // Given
        let data = Data.randomData(length: 1_024)
        var fileBuffer = Internals.FileBuffer(data)

        let writeData = Data.randomData(length: 64)

        // When
        fileBuffer.setData(writeData, at: data.count - 32)

        // Then
        #expect(fileBuffer.writableBytes == writeData.count - 32)

        fileBuffer.moveReaderIndex(to: fileBuffer.writerIndex - 32)
        fileBuffer.moveWriterIndex(to: fileBuffer.writerIndex + fileBuffer.writableBytes)

        #expect(fileBuffer.readData(writeData.count) == writeData)
    }

    @Test
    func fileBuffer_whenSetBytesWhenMovingWriterIndex() async throws {
        // Given
        let data = Data.randomData(length: 1_024)
        var fileBuffer = Internals.FileBuffer(data)

        let writeBytes = Array(Data.randomData(length: 64))

        // When
        fileBuffer.moveWriterIndex(to: data.count - 32)
        fileBuffer.setBytes(writeBytes)

        // Then
        #expect(fileBuffer.writableBytes == writeBytes.count)

        fileBuffer.moveReaderIndex(to: fileBuffer.writerIndex)
        fileBuffer.moveWriterIndex(to: fileBuffer.writerIndex + fileBuffer.writableBytes)

        #expect(fileBuffer.readBytes(writeBytes.count) == writeBytes)
    }

    @Test
    func fileBuffer_whenSetBytesAtWriterIndex() async throws {
        // Given
        let data = Data.randomData(length: 1_024)
        var fileBuffer = Internals.FileBuffer(data)

        let writeBytes = Array(Data.randomData(length: 64))

        // When
        fileBuffer.setBytes(writeBytes, at: data.count - 32)

        // Then
        #expect(fileBuffer.writableBytes == writeBytes.count - 32)

        fileBuffer.moveReaderIndex(to: fileBuffer.writerIndex - 32)
        fileBuffer.moveWriterIndex(to: fileBuffer.writerIndex + fileBuffer.writableBytes)

        #expect(fileBuffer.readBytes(writeBytes.count) == writeBytes)
    }

    @Test
    func fileBuffer_whenRacingImmutable() async throws {
        // Given
        let fileBuffer = Internals.FileBuffer(Data.randomData(length: 1_024))

        // When
        let datas = await withTaskGroup(of: Data?.self) { group in
            for index in 0 ..< 1_024 {
                group.addTask {
                    return fileBuffer.getData(at: index, length: 1_024 - index)
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
