/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class BaseURLTests: XCTestCase {

    func testHttpURL() async throws {
        // Given
        let scheme = URLScheme.http
        let host = "google.com"

        // When
        let baseURL = BaseURL(scheme, host: host)
        let resolved = try await resolve(baseURL)

        // Then
        XCTAssertEqual(resolved.request.url, "\(scheme)://\(host)")
    }

    func testHttpsURL() async throws {
        // Given
        let scheme = URLScheme.https
        let host = "google.com"

        // When
        let baseURL = BaseURL(scheme, host: host)
        let resolved = try await resolve(baseURL)

        // Then
        XCTAssertEqual(resolved.request.url, "\(scheme)://\(host)")
    }

    func testFtpURL() async throws {
        // Given
        let scheme = URLScheme.ftp
        let host = "google.com"

        // When
        let baseURL = BaseURL(scheme, host: host)
        let resolved = try await resolve(baseURL)

        // Then
        XCTAssertEqual(resolved.request.url, "\(scheme)://\(host)")
    }

    func testSmtpURL() async throws {
        // Given
        let scheme = URLScheme.smtp
        let host = "google.com"

        // When
        let baseURL = BaseURL(scheme, host: host)
        let resolved = try await resolve(baseURL)

        // Then
        XCTAssertEqual(resolved.request.url, "\(scheme)://\(host)")
    }

    func testImapURL() async throws {
        // Given
        let scheme = URLScheme.imap
        let host = "google.com"

        // When
        let baseURL = BaseURL(scheme, host: host)
        let resolved = try await resolve(baseURL)

        // Then
        XCTAssertEqual(resolved.request.url, "\(scheme)://\(host)")
    }

    func testPopURL() async throws {
        // Given
        let scheme = URLScheme.pop
        let host = "google.com"

        // When
        let baseURL = BaseURL(scheme, host: host)
        let resolved = try await resolve(baseURL)

        // Then
        XCTAssertEqual(resolved.request.url, "\(scheme)://\(host)")
    }

    func testDnsURL() async throws {
        // Given
        let scheme = URLScheme.dns
        let host = "google.com"

        // When
        let baseURL = BaseURL(scheme, host: host)
        let resolved = try await resolve(baseURL)

        // Then
        XCTAssertEqual(resolved.request.url, "\(scheme)://\(host)")
    }

    func testSshURL() async throws {
        // Given
        let scheme = URLScheme.ssh
        let host = "google.com"

        // When
        let baseURL = BaseURL(scheme, host: host)
        let resolved = try await resolve(baseURL)

        // Then
        XCTAssertEqual(resolved.request.url, "\(scheme)://\(host)")
    }

    func testTelnetURL() async throws {
        // Given
        let scheme = URLScheme.telnet
        let host = "google.com"

        // When
        let baseURL = BaseURL(scheme, host: host)
        let resolved = try await resolve(baseURL)

        // Then
        XCTAssertEqual(resolved.request.url, "\(scheme)://\(host)")
    }

    func testDefaultURLWithoutProtocol() async throws {
        // Given
        let host = "google.com.br"

        // When
        let baseURL = BaseURL(host)
        let resolved = try await resolve(baseURL)

        // Then
        XCTAssertEqual(resolved.request.url, "https://google.com.br")
    }

    func testCollisionBaseURL() async throws {
        // Given
        let host1 = "apple.com"
        let host2 = "google.com"

        // When
        let resolved = try await resolve(TestProperty {
            BaseURL(.ftp, host: host1)
            BaseURL(host2)
        })

        // Then
        XCTAssertEqual(resolved.request.url, "https://google.com")
    }

    func testURL_whenIncludingScheme() async throws {
        // Given
        let baseURL = "https://www.apple.com"

        do {
            // When
            _ = try await resolve(TestProperty {
                BaseURL(baseURL)
            })

            // Then
            XCTFail("Not expecting success")
        } catch let error as BaseURLError {
            XCTAssertEqual(error.context, .invalidHost)
            XCTAssertEqual(error.baseURL, baseURL)
            XCTAssertEqual(error.errorDescription, """
                Invalid host string: The url scheme should not be \
                included; BaseURL: \(baseURL)
                """
            )
        } catch {
            throw error
        }
    }

    func testURL_whenEmptyString() async throws {
        // Given
        let baseURL = ""

        do {
            // When
            _ = try await resolve(TestProperty {
                BaseURL(baseURL)
            })

            // Then
            XCTFail("Not expecting success")
        } catch let error as BaseURLError {
            XCTAssertEqual(error.context, .unexpectedHost)
            XCTAssertEqual(error.baseURL, baseURL)
            XCTAssertEqual(error.errorDescription, """
                Unexpected format for host string: Could not extract the \
                host; BaseURL: \(baseURL)
                """
            )
        } catch {
            throw error
        }
    }

    func testNeverBody() async throws {
        // Given
        let property = BaseURL("apple.com")

        // Then
        try await assertNever(property.body)
    }
}
