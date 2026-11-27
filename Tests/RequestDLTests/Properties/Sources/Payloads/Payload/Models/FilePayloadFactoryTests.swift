//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.URL
#endif

struct FilePayloadFactoryTests {

    private let url = URL(fileURLWithPath: "/tmp/report.bin")

    /// On a 32-bit platform (watchOS' `arm64_32`) `Int.max` is 2 GiB, and a file of 3 GiB cannot be
    /// created on the machine that runs the tests, so the limit stands in for it.
    @Test
    func aFileThatDoesNotFitAnInt_isRefused() {
        // Given: an `Int` of 100, in place of a 32-bit one
        // Then
        do {
            try FilePayloadFactory.validate(size: 101, of: url, limit: 100)
            Issue.record("Not expecting success")
        } catch let error as FilePayloadError {
            #expect(error.url == url)

            guard case .tooLarge(let size) = error.context else {
                Issue.record("Expected .tooLarge, got \(error.context)")
                return
            }

            #expect(size == 101)
            #expect(error.description.contains("101 bytes"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test(arguments: [0, 1, 99, 100] as [Int64])
    func aFileThatFitsAnInt_isAccepted(_ size: Int64) throws {
        try FilePayloadFactory.validate(size: size, of: url, limit: 100)
    }

    @Test
    func aFileOfAnyRepresentableSize_isAcceptedWithTheDefaultLimit() throws {
        try FilePayloadFactory.validate(size: Int64(Int.max), of: url)
    }
}
