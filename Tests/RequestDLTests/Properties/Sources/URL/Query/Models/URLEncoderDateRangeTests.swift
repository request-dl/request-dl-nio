//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Date
#endif

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// A `Date` that does not fit the strategy is an error of the encoder, not a crash: `Int64(_:)`
/// traps on NaN, on infinity and on a `Double` beyond `Int64.max`, and a date read from a server
/// can be any of them when it is sent back as a cursor.
struct URLEncoderDateRangeTests {

    // Swift Testing's exit tests need to spawn a real child process, which only macOS and Linux
    // support here (see `ReadingModeTests`). They also keep a regression from taking the test
    // runner down with it: the child traps, the test fails, the run goes on. The closure runs in
    // that child process, so it cannot capture anything from this scope.
    #if os(macOS) || os(Linux)
    @Test
    func secondsSince1970_whenTheDateIsNotRepresentable_throwsInvalidDate() async {
        await #expect(processExitsWith: .success) {
            for seconds in [Double.nan, .infinity, -.infinity, 1e19, -1e19] {
                let encoder = URLEncoder()
                encoder.dateEncodingStrategy = .secondsSince1970

                do {
                    _ = try encoder.encode(Date(timeIntervalSince1970: seconds), forKey: "since")
                    exit(1)
                } catch let error as URLEncoderError {
                    guard error.errorType == .invalidDate else { exit(2) }
                } catch {
                    exit(3)
                }
            }
        }
    }

    @Test
    func millisecondsSince1970_whenTheDateIsNotRepresentable_throwsInvalidDate() async {
        await #expect(processExitsWith: .success) {
            // 1e16 seconds is finite and fits in an `Int64` as seconds, not as milliseconds.
            for seconds in [Double.nan, .infinity, -.infinity, 1e16, -1e16] {
                let encoder = URLEncoder()
                encoder.dateEncodingStrategy = .millisecondsSince1970

                do {
                    _ = try encoder.encode(Date(timeIntervalSince1970: seconds), forKey: "since")
                    exit(1)
                } catch let error as URLEncoderError {
                    guard error.errorType == .invalidDate else { exit(2) }
                } catch {
                    exit(3)
                }
            }
        }
    }

    @Test
    func iso8601_whenTheDateIsNotRepresentable_throwsInvalidDate() async {
        await #expect(processExitsWith: .success) {
            for seconds in [Double.nan, .infinity, -.infinity, 1e19, -1e19] {
                let encoder = URLEncoder()
                encoder.dateEncodingStrategy = .iso8601

                do {
                    _ = try encoder.encode(Date(timeIntervalSince1970: seconds), forKey: "since")
                    exit(1)
                } catch let error as URLEncoderError {
                    guard error.errorType == .invalidDate else { exit(2) }
                } catch {
                    exit(3)
                }
            }
        }
    }
    #endif

    /// The largest values that do fit are still encoded, same as before.
    @Test
    func secondsSince1970_whenTheDateIsFarButRepresentable_isEncoded() throws {
        // Given
        let encoder = URLEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970

        // When
        let sut = try encoder.encode(Date(timeIntervalSince1970: 9e18), forKey: "since").joined()

        // Then
        #expect(sut == "since=9000000000000000000")
    }

    @Test
    func millisecondsSince1970_whenTheDateIsFarButRepresentable_isEncoded() throws {
        // Given
        let encoder = URLEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970

        // When
        let sut = try encoder.encode(Date(timeIntervalSince1970: 9e15), forKey: "since").joined()

        // Then
        #expect(sut == "since=9000000000000000000")
    }

    @Test
    func iso8601_whenTheDateIsFarButRepresentable_isEncoded() throws {
        // Given
        let encoder = URLEncoder()
        encoder.dateEncodingStrategy = .iso8601

        // When
        let sut = try encoder.encode(Date(timeIntervalSince1970: 9e18), forKey: "since")

        // Then
        #expect(!sut.isEmpty)
    }

    @Test
    func iso8601_whenTheDateIsValid_keepsItsFormat() throws {
        // Given
        let encoder = URLEncoder()
        encoder.dateEncodingStrategy = .iso8601

        // When
        let sut = try encoder.encode(Date(timeIntervalSince1970: 1_698_400_800), forKey: "since").joined()

        // Then
        #expect(sut == "since=2023-10-27T10%3A00%3A00Z")
    }
}
