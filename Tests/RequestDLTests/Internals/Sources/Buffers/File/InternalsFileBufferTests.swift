//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import struct Foundation.URL
import struct Foundation.UUID
#endif
import SystemPackage
import Testing

@testable import RequestDL

struct InternalsFileBufferTests {

    /// Owns a scratch file for the lifetime of one test.
    ///
    /// - Important: Must write into the system temporary directory, not a path derived from
    /// `#file` — that puts test artefacts in the source tree, and combined with the fire and
    /// forget teardown below leaves stray `.txt` files accumulating in the repository.
    final class FileURLManager: Sendable {

        let url: URL

        init() async throws {
            url = URL(fileURLWithPath: FilePath.temporaryDirectory.string, isDirectory: true)
                .appendingPathComponent("FileBufferTests.\(UUID().uuidString).txt")

            try await url.removeIfNeeded()
        }

        deinit {
            let url = self.url
            Task.detached { try? await url.removeIfNeeded() }
        }
    }

    @Test
    func fileBuffer_whenInitURL_shouldBeEmpty() async throws {
        // Given
        let fileURLManager = try await FileURLManager()
        defer { _ = fileURLManager }

        let fileURL = fileURLManager.url
        let fileBuffer = await Internals.FileBuffer(fileURL)

        // When
        let writerIndex = fileBuffer.writerIndex
        let readerIndex = fileBuffer.readerIndex
        let readableBytes = fileBuffer.readableBytes
        let overwritableBytes = await fileBuffer.overwritableBytes
        let estimatedBytes = await fileBuffer.estimatedBytes

        // Then
        #expect(writerIndex == .zero)
        #expect(readerIndex == .zero)
        #expect(readableBytes == .zero)
        #expect(overwritableBytes == .zero)
        #expect(estimatedBytes == .zero)
    }

    @Test
    func fileBuffer_whenContainsData_shouldWriterBeAtEndAndReaderAtZero() async throws {
        // Given
        let fileURLManager = try await FileURLManager()
        defer { _ = fileURLManager }

        let fileURL = fileURLManager.url
        let data = Data("Hello world".utf8)
        try data.write(to: fileURL)

        let fileBuffer = await Internals.FileBuffer(fileURL)

        // When
        let writerIndex = fileBuffer.writerIndex
        let readerIndex = fileBuffer.readerIndex
        let readableBytes = fileBuffer.readableBytes
        let overwritableBytes = await fileBuffer.overwritableBytes

        // Then
        #expect(writerIndex == data.count)
        #expect(readerIndex == .zero)
        #expect(readableBytes == data.count)
        #expect(overwritableBytes == .zero)
    }

    @Test
    func fileBuffer_whenContainsData_shouldReadDataAvailable() async throws {
        // Given
        let fileURLManager = try await FileURLManager()
        defer { _ = fileURLManager }

        let fileURL = fileURLManager.url
        let data = Data("Hello world".utf8)
        try data.write(to: fileURL)

        var fileBuffer = await Internals.FileBuffer(fileURL)

        // When
        let readData = await fileBuffer.readData(data.count)

        // Then
        #expect(fileBuffer.writerIndex == data.count)
        #expect(fileBuffer.readerIndex == data.count)
        #expect(fileBuffer.readableBytes == .zero)
        await #expect(fileBuffer.overwritableBytes == .zero)
        #expect(readData == data)
        await #expect(fileBuffer.estimatedBytes == data.count)
    }

    @Test
    func fileBuffer_whenContainsDataMovingReaderIndex_shouldReadableBytesBeUpdated() async throws {
        // Given
        let fileURLManager = try await FileURLManager()
        defer { _ = fileURLManager }

        let fileURL = fileURLManager.url
        let data = Data("Hello world".utf8)
        try data.write(to: fileURL)

        let index = 2
        var fileBuffer = await Internals.FileBuffer(fileURL)

        // When
        let readableIndex = fileBuffer.readableBytes
        fileBuffer.moveReaderIndex(to: index)

        // Then
        #expect(readableIndex == data.count)
        #expect(fileBuffer.writerIndex == data.count)
        #expect(fileBuffer.readerIndex == index)
        #expect(fileBuffer.readableBytes == data.count - index)
        await #expect(fileBuffer.overwritableBytes == .zero)
    }

    @Test
    func fileBuffer_whenContainsDataMovingWriterIndex_shouldWritableBytesBeUpdated() async throws {
        // Given
        let fileURLManager = try await FileURLManager()
        defer { _ = fileURLManager }

        let fileURL = fileURLManager.url
        let data = Data("Hello world".utf8)
        try data.write(to: fileURL)

        let index = data.count - 2
        var fileBuffer = await Internals.FileBuffer(fileURL)

        // When
        let overwritableBytes = await fileBuffer.overwritableBytes
        fileBuffer.moveWriterIndex(to: index)

        // Then
        #expect(overwritableBytes == .zero)
        #expect(fileBuffer.writerIndex == index)
        #expect(fileBuffer.readerIndex == .zero)
        #expect(fileBuffer.readableBytes == index)
        await #expect(fileBuffer.overwritableBytes == data.count - index)
    }

    @Test
    func fileBuffer_whenWritingWithTwoCopy_shouldWritableBytesBeUpdated() async throws {
        // Given
        let fileURLManager = try await FileURLManager()
        defer { _ = fileURLManager }

        let fileURL = fileURLManager.url
        let data = Data("Hello World".utf8)
        let sut1 = await Internals.FileBuffer(fileURL)
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
        await #expect(sut1.overwritableBytes == data.count)
        #expect(sut1.readableBytes == .zero)
    }

    @Test
    func fileBuffer_whenWritingWithTwoInstances_shouldWritableBytesBeUpdated() async throws {
        // Given
        let fileURLManager = try await FileURLManager()
        defer { _ = fileURLManager }

        let fileURL = fileURLManager.url
        let data = Data("Hello World".utf8)
        let sut1 = await Internals.FileBuffer(fileURL)
        var sut2 = await Internals.FileBuffer(fileURL)

        // When
        let writerIndex = sut1.writerIndex
        let readerIndex = sut1.readerIndex

        await sut2.writeData(data)

        // Then
        #expect(writerIndex == sut1.writerIndex)
        #expect(readerIndex == sut1.readerIndex)
        #expect(sut2.writerIndex == data.count)
        #expect(sut2.readableBytes == data.count)
        await #expect(sut1.overwritableBytes == data.count)
        #expect(sut1.readableBytes == .zero)
    }

    @Test
    func fileBuffer_whenWritingWithTwoInstancesSimultaneos_shouldWritableBytesBeUpdated() async throws {
        // Given
        let fileURLManager = try await FileURLManager()
        defer { _ = fileURLManager }

        let fileURL = fileURLManager.url
        let data = Data("Hello World".utf8)
        let writeSliceIndex = 3
        var sut1 = await Internals.FileBuffer(fileURL)
        var sut2 = await Internals.FileBuffer(fileURL)

        // When
        await sut2.writeData(data)
        await sut1.writeData(data[0..<writeSliceIndex])

        // Then
        #expect(sut2.writerIndex == data.count)
        #expect(sut2.readableBytes == data.count)
        await #expect(sut1.overwritableBytes == data.count - writeSliceIndex)
        #expect(sut1.readableBytes == writeSliceIndex)
    }

    @Test
    func fileBuffer_whenWritingWithTwoInstancesSimultaneosBytes_shouldWritableBytesBeUpdated() async throws {
        // Given
        let fileURLManager = try await FileURLManager()
        defer { _ = fileURLManager }

        let fileURL = fileURLManager.url
        let data = Data("Hello World".utf8)
        let writeSliceIndex = 3
        var sut1 = await Internals.FileBuffer(fileURL)
        var sut2 = await Internals.FileBuffer(fileURL)

        // When
        await sut2.writeBytes(data)
        await sut1.writeBytes(data[0..<writeSliceIndex])

        // Then
        #expect(sut2.writerIndex == data.count)
        #expect(sut2.readableBytes == data.count)
        await #expect(sut1.overwritableBytes == data.count - writeSliceIndex)
        #expect(sut1.readableBytes == writeSliceIndex)
    }

    @Test
    func fileBuffer_whenReadingWithTwoCopy_shouldReadableBytesBeUpdated() async throws {
        // Given
        let fileURLManager = try await FileURLManager()
        defer { _ = fileURLManager }

        let fileURL = fileURLManager.url
        let data = Data("Hello World".utf8)
        try data.write(to: fileURL)

        let sut1 = await Internals.FileBuffer(fileURL)
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
        await #expect(sut1.overwritableBytes == .zero)
        #expect(sut1.readableBytes == data.count)
    }

    @Test
    func fileBuffer_whenReadingWithTwoInstances_shouldReadableBytesBeUpdated() async throws {
        // Given
        let fileURLManager = try await FileURLManager()
        defer { _ = fileURLManager }

        let fileURL = fileURLManager.url
        let data = Data("Hello World".utf8)
        try data.write(to: fileURL)

        let sut1 = await Internals.FileBuffer(fileURL)
        var sut2 = await Internals.FileBuffer(fileURL)

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
        await #expect(sut1.overwritableBytes == .zero)
        #expect(sut1.readableBytes == data.count)
    }

    @Test
    func fileBuffer_whenReadingWithTwoInstancesSimultaneos_shouldReadableBytesBeUpdated() async throws {
        // Given
        let fileURLManager = try await FileURLManager()
        defer { _ = fileURLManager }

        let fileURL = fileURLManager.url
        let data = Data("Hello World".utf8)
        try data.write(to: fileURL)

        let readSliceIndex = 3
        var sut1 = await Internals.FileBuffer(fileURL)
        var sut2 = await Internals.FileBuffer(fileURL)

        // When
        let readData2 = await sut2.readData(data.count)
        let readData1 = await sut1.readData(readSliceIndex)

        // Then
        #expect(readData1 == data[0..<readSliceIndex])
        #expect(sut1.writerIndex == data.count)
        #expect(sut1.readableBytes == data.count - readSliceIndex)
        await #expect(sut1.overwritableBytes == .zero)

        #expect(readData2 == data)
        #expect(sut2.writerIndex == data.count)
        #expect(sut2.readableBytes == .zero)
        await #expect(sut2.overwritableBytes == .zero)
    }

    @Test
    func fileBuffer_whenReadingWithTwoInstancesSimultaneosBytes_shouldReadableBytesBeUpdated() async throws {
        // Given
        let fileURLManager = try await FileURLManager()
        defer { _ = fileURLManager }

        let fileURL = fileURLManager.url
        let data = Data("Hello World".utf8)
        try data.write(to: fileURL)

        let readSliceIndex = 3
        var sut1 = await Internals.FileBuffer(fileURL)
        var sut2 = await Internals.FileBuffer(fileURL)

        // When
        let readBytes2 = await sut2.readBytes(data.count)
        let readBytes1 = await sut1.readBytes(readSliceIndex)

        // Then
        #expect(readBytes1 == Array(data[0..<readSliceIndex]))
        #expect(sut1.writerIndex == data.count)
        #expect(sut1.readableBytes == data.count - readSliceIndex)
        await #expect(sut1.overwritableBytes == .zero)

        #expect(readBytes2 == Array(data))
        #expect(sut2.writerIndex == data.count)
        #expect(sut2.readableBytes == .zero)
        await #expect(sut2.overwritableBytes == .zero)
    }

    @Test
    func fileBuffer_whenWritingAndReadingSimultaneos_shouldBytesBeUpdatedAndOverrided() async throws {
        // Given
        let fileURLManager = try await FileURLManager()
        defer { _ = fileURLManager }

        let fileURL = fileURLManager.url
        let data = Data("Hello World".utf8)
        let overrideData = Data("Earth".utf8)

        var sut1 = await Internals.FileBuffer(fileURL)
        var sut2 = await Internals.FileBuffer(fileURL)

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
        await #expect(sut1.overwritableBytes == data.count - overrideData.count)
        #expect(sut1.readableBytes == .zero)

        #expect(sut2.writerIndex == data.count)
        #expect(sut2.readerIndex == data.count)
        await #expect(sut2.overwritableBytes == .zero)
        #expect(sut2.readableBytes == .zero)
    }

    @Test
    func fileBuffer_whenWritingFromOtherFileBuffer_shouldHaveContentsAppended() async throws {
        // Given
        let fileURLManager = try await FileURLManager()
        defer { _ = fileURLManager }

        let fileURL = fileURLManager.url
        let otherFile =
            fileURL
            .deletingLastPathComponent()
            .appendingPathComponent("FileBufferOtherFile.txt")

        defer { otherFile.scheduleRemoval() }

        let data = Data("Hello World".utf8)
        let otherData = Data("Earth is a small planet to live".utf8)

        var sut1 = await Internals.FileBuffer(fileURL)
        var sut2 = await Internals.FileBuffer(otherFile)

        // When
        await sut1.writeData(data)
        await sut2.writeData(otherData)

        await sut1.writeBuffer(&sut2)

        // Then
        #expect(sut1.writerIndex == data.count + otherData.count)
        #expect(sut2.writerIndex == otherData.count)

        await #expect(sut1.overwritableBytes == .zero)
        await #expect(sut2.overwritableBytes == .zero)

        #expect(sut1.readerIndex == .zero)
        #expect(sut2.readerIndex == otherData.count)

        await #expect(sut1.readData(sut1.readableBytes) == data + otherData)
    }

    @Test
    func fileBuffer_whenInitEmpty_shouldBeEmpty() async throws {
        // Given
        let fileBuffer = await Internals.FileBuffer()

        // When
        let writerIndex = fileBuffer.writerIndex
        let readerIndex = fileBuffer.readerIndex
        let readableBytes = fileBuffer.readableBytes
        let overwritableBytes = await fileBuffer.overwritableBytes

        // Then
        #expect(writerIndex == .zero)
        #expect(readerIndex == .zero)
        #expect(readableBytes == .zero)
        #expect(overwritableBytes == .zero)
    }

    @Test
    func fileBuffer_whenInitData_shouldReadContents() async throws {
        // Given
        let data = Data("Hello World".utf8)
        var fileBuffer = await Internals.FileBuffer(data)

        // When
        let readData = await fileBuffer.readData(fileBuffer.readableBytes)

        // Then
        #expect(readData == data)
        #expect(fileBuffer.writerIndex == data.count)
        #expect(fileBuffer.readerIndex == data.count)
        #expect(fileBuffer.readableBytes == .zero)
        await #expect(fileBuffer.overwritableBytes == .zero)
    }

    @Test
    func fileBuffer_whenInitBytes_shouldReadContents() async throws {
        // Given
        let data = Data("Hello World".utf8)
        let bytes = Array(data)
        var fileBuffer = await Internals.FileBuffer(BytesSequence(data))

        // When
        let readBytes = await fileBuffer.readBytes(fileBuffer.readableBytes)

        // Then
        #expect(readBytes == bytes)
        #expect(fileBuffer.writerIndex == bytes.count)
        #expect(fileBuffer.readerIndex == bytes.count)
        #expect(fileBuffer.readableBytes == .zero)
        await #expect(fileBuffer.overwritableBytes == .zero)
    }

    @Test
    func fileBuffer_whenInitString_shouldReadContents() async throws {
        // Given
        let string: String = "Hello World"
        var fileBuffer = await Internals.FileBuffer(string)

        // When
        let readData = await fileBuffer.readData(fileBuffer.readableBytes)

        // Then
        #expect(readData == Data(string.utf8))
        #expect(fileBuffer.writerIndex == string.count)
        #expect(fileBuffer.readerIndex == string.count)
        #expect(fileBuffer.readableBytes == .zero)
        await #expect(fileBuffer.overwritableBytes == .zero)
    }

    @Test
    func fileBuffer_whenInitStaticString_shouldReadContents() async throws {
        // Given
        let string: StaticString = "Hello World"
        var fileBuffer = await Internals.FileBuffer(string)

        // When
        let readData = await fileBuffer.readData(fileBuffer.readableBytes)

        // Then
        #expect(readData == "\(string)".data(using: .utf8))
        #expect(fileBuffer.writerIndex == string.utf8CodeUnitCount)
        #expect(fileBuffer.readerIndex == string.utf8CodeUnitCount)
        #expect(fileBuffer.readableBytes == .zero)
        await #expect(fileBuffer.overwritableBytes == .zero)
    }

    @Test
    func fileBuffer_whenInitFileBuffer_shouldReadContents() async throws {
        // Given
        let data = Data("Hello World".utf8)
        let fileBuffer = await Internals.FileBuffer(data)
        var sut1 = await Internals.FileBuffer(fileBuffer)

        // When
        let readData = await sut1.readData(sut1.readableBytes)

        // Then
        #expect(sut1.writerIndex == fileBuffer.writerIndex)
        #expect(readData == data)
    }

    @Test
    func fileBuffer_whenInitByteURL_shouldBeEmpty() async throws {
        // Given
        let url = Internals.ByteURL()

        let fileBuffer = await Internals.FileBuffer(url)

        // When
        let writerIndex = fileBuffer.writerIndex
        let readerIndex = fileBuffer.readerIndex
        let readableBytes = fileBuffer.readableBytes
        let overwritableBytes = await fileBuffer.overwritableBytes

        // Then
        #expect(writerIndex == .zero)
        #expect(readerIndex == .zero)
        #expect(readableBytes == .zero)
        #expect(overwritableBytes == .zero)
    }

    @Test
    func fileBuffer_whenInitDataBuffer_shouldBeEqual() async throws {
        // Given
        let data = await Data.randomData(length: 1_000_000)
        let fileBuffer = await Internals.FileBuffer(Internals.DataBuffer(data))

        // When
        let writerIndex = fileBuffer.writerIndex
        let readerIndex = fileBuffer.readerIndex
        let readableBytes = fileBuffer.readableBytes
        let overwritableBytes = await fileBuffer.overwritableBytes

        // Then
        #expect(writerIndex == data.count)
        #expect(readerIndex == .zero)
        #expect(readableBytes == data.count)
        #expect(overwritableBytes == .zero)
    }

    @Test
    func fileBuffer_whenReadZeroBytes_shouldBeNil() async throws {
        // Given
        var dataBuffer = await Internals.FileBuffer()

        // When
        let data = await dataBuffer.readData(.zero)

        // Then
        #expect(data == nil)
    }

    @Test
    func fileBuffer_whenReadDataOutOfBounds() async throws {
        // Given
        var fileBuffer = await Internals.FileBuffer(
            Data.randomData(length: 64)
        )

        // When
        let data = await fileBuffer.readData(72)

        // Then
        #expect(data == nil)
    }

    @Test
    func fileBuffer_whenReadBytesOutOfBounds() async throws {
        // Given
        var fileBuffer = await Internals.FileBuffer(
            Data.randomData(length: 64)
        )

        // When
        let bytes = await fileBuffer.readBytes(72)

        // Then
        #expect(bytes == nil)
    }

    @Test
    func fileBuffer_whenGetData() async throws {
        // Given
        let data = await Data.randomData(length: 1_024)
        let fileBuffer = await Internals.FileBuffer(data)

        // Then
        await #expect(fileBuffer.getData() == data)
    }

    @Test
    func fileBuffer_whenGetDataByMovingReaderIndex() async throws {
        // Given
        let data = await Data.randomData(length: 1_024)
        var fileBuffer = await Internals.FileBuffer(data)

        // When
        fileBuffer.moveReaderIndex(to: 64)

        // Then
        await #expect(fileBuffer.getData() == data[64..<data.count])
    }

    @Test
    func fileBuffer_whenGetBytes() async throws {
        // Given
        let data = await Data.randomData(length: 1_024)
        let fileBuffer = await Internals.FileBuffer(data)

        // Then
        await #expect(fileBuffer.getBytes() == Array(data))
    }

    @Test
    func fileBuffer_whenGetBytesByMovingReaderIndex() async throws {
        // Given
        let data = await Data.randomData(length: 1_024)
        var fileBuffer = await Internals.FileBuffer(data)

        // When
        fileBuffer.moveReaderIndex(to: 64)

        // Then
        await #expect(fileBuffer.getBytes() == Array(data[64..<data.count]))
    }

    @Test
    func fileBuffer_whenGetBytesAtIndexWithLength() async throws {
        // Given
        let data = await Data.randomData(length: 1_024)
        var fileBuffer = await Internals.FileBuffer(data)

        // When
        fileBuffer.moveReaderIndex(to: 64)

        // Then

        await #expect(fileBuffer.getBytes(at: 32, length: 64) == Array(data[32..<96]))
    }

    @Test
    func fileBuffer_whenGetDataAtIndexWithLength() async throws {
        // Given
        let data = await Data.randomData(length: 1_024)
        var fileBuffer = await Internals.FileBuffer(data)

        // When
        fileBuffer.moveReaderIndex(to: 64)

        // Then

        await #expect(fileBuffer.getData(at: 32, length: 64) == data[32..<96])
    }

    @Test
    func fileBuffer_whenSetDataAtWriterIndex() async throws {
        // Given
        let data = await Data.randomData(length: 1_024)
        var fileBuffer = await Internals.FileBuffer(data)

        let writeData = await Data.randomData(length: 64)

        // When
        try await fileBuffer.setData(writeData, at: data.count - 32)

        // Then
        await #expect(fileBuffer.overwritableBytes == writeData.count - 32)

        fileBuffer.moveReaderIndex(to: fileBuffer.writerIndex - 32)
        await fileBuffer.moveWriterIndex(to: fileBuffer.writerIndex + fileBuffer.overwritableBytes)

        await #expect(fileBuffer.readData(writeData.count) == writeData)
    }

    @Test
    func fileBuffer_whenSetBytesAtWriterIndex() async throws {
        // Given
        let data = await Data.randomData(length: 1_024)
        var fileBuffer = await Internals.FileBuffer(data)

        let writeBytes = await Array(Data.randomData(length: 64))

        // When
        await fileBuffer.setBytes(writeBytes, at: data.count - 32)

        // Then
        await #expect(fileBuffer.overwritableBytes == writeBytes.count - 32)

        fileBuffer.moveReaderIndex(to: fileBuffer.writerIndex - 32)
        await fileBuffer.moveWriterIndex(to: fileBuffer.writerIndex + fileBuffer.overwritableBytes)

        await #expect(fileBuffer.readBytes(writeBytes.count) == writeBytes)
    }

    @Test
    func fileBuffer_whenRacingImmutable() async throws {
        // Given
        let fileBuffer = await Internals.FileBuffer(Data.randomData(length: 1_024))

        // When
        let datas = await withTaskGroup(of: Data?.self) { group in
            for index in 0..<1_024 {
                group.addTask {
                    await fileBuffer.getData(at: index, length: 1_024 - index)
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
