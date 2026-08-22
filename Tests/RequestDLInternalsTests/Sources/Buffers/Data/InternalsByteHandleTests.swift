//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDLInternals

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

struct InternalsByteHandleTests {

    @Test
    func seek_afterClose_throwsClosedError() throws {
        let handle = Internals.ByteHandle(forWritingTo: .init())
        try handle.close()

        #expect(throws: Error.self) {
            try handle.seek(toOffset: .zero)
        }
    }

    @Test
    func offset_afterClose_throwsClosedError() throws {
        let handle = Internals.ByteHandle(forReadingFrom: .init())
        try handle.close()

        #expect(throws: Error.self) {
            try handle.offset()
        }
    }

    @Test
    func read_afterClose_throwsClosedError() throws {
        let handle = Internals.ByteHandle(forReadingFrom: .init())
        try handle.close()

        #expect(throws: Error.self) {
            _ = try handle.read(upToCount: 1)
        }
    }

    @Test
    func read_onWriteHandle_throwsInvalidModeErrorDescribingBothModes() throws {
        let handle = Internals.ByteHandle(forWritingTo: .init())

        var thrownError: Error?

        do {
            _ = try handle.read(upToCount: 1)
        } catch {
            thrownError = error
        }

        let description = thrownError.map(String.init(describing:)) ?? ""
        #expect(description.contains("reading"))
        #expect(description.contains("writing"))
    }

    @Test
    func write_afterClose_throwsClosedError() throws {
        let handle = Internals.ByteHandle(forWritingTo: .init())
        try handle.close()

        #expect(throws: Error.self) {
            try handle.write(contentsOf: Data([0x01]))
        }
    }

    @Test
    func write_onReadHandle_throwsInvalidModeErrorDescribingBothModes() throws {
        let handle = Internals.ByteHandle(forReadingFrom: .init())

        var thrownError: Error?

        do {
            try handle.write(contentsOf: Data([0x01]))
        } catch {
            thrownError = error
        }

        let description = thrownError.map(String.init(describing:)) ?? ""
        #expect(description.contains("writing"))
        #expect(description.contains("reading"))
    }

    @Test
    func close_afterClose_throwsClosedErrorWithDescription() throws {
        let handle = Internals.ByteHandle(forWritingTo: .init())
        try handle.close()

        var thrownError: Error?

        do {
            try handle.close()
        } catch {
            thrownError = error
        }

        let description = thrownError.map(String.init(describing:)) ?? ""
        #expect(description.contains("already been closed"))
    }

    @Test
    func write_afterSeekingPastEnd_fillsGapWithZeros() throws {
        let url = Internals.ByteURL()
        let writer = Internals.ByteHandle(forWritingTo: url)

        try writer.seek(toOffset: 4)
        try writer.write(contentsOf: Data([0xFF]))

        let reader = Internals.ByteHandle(forReadingFrom: url)
        let data = try reader.read(upToCount: 5)

        #expect(data == Data([0x00, 0x00, 0x00, 0x00, 0xFF]))
    }

    @Test
    func read_withCountZero_returnsNil() throws {
        let url = Internals.ByteURL()
        let writer = Internals.ByteHandle(forWritingTo: url)
        try writer.write(contentsOf: Data([0x01]))

        let reader = Internals.ByteHandle(forReadingFrom: url)
        let data = try reader.read(upToCount: .zero)

        #expect(data == nil)
    }

    @Test
    func read_pastEnd_returnsNil() throws {
        let url = Internals.ByteURL()
        let writer = Internals.ByteHandle(forWritingTo: url)
        try writer.write(contentsOf: Data([0x01]))

        let reader = Internals.ByteHandle(forReadingFrom: url)
        try reader.seek(toOffset: 100)
        let data = try reader.read(upToCount: 1)

        #expect(data == nil)
    }
}
