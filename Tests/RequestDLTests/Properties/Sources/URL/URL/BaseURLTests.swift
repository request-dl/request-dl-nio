/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct BaseURLTests {

    @Test
    func httpURL() async throws {
        // Given
        let scheme = URLScheme.http
        let host = "google.com"

        // When
        let baseURL = BaseURL(scheme, host: host)
        let resolved = try await resolve(baseURL)

        // Then
        #expect(resolved.request.url == "\(scheme)://\(host)")
    }

    @Test
    func httpsURL() async throws {
        // Given
        let scheme = URLScheme.https
        let host = "google.com"

        // When
        let baseURL = BaseURL(scheme, host: host)
        let resolved = try await resolve(baseURL)

        // Then
        #expect(resolved.request.url == "\(scheme)://\(host)")
    }

    @Test
    func ftpURL() async throws {
        // Given
        let scheme = URLScheme.ftp
        let host = "google.com"

        // When
        let baseURL = BaseURL(scheme, host: host)
        let resolved = try await resolve(baseURL)

        // Then
        #expect(resolved.request.url == "\(scheme)://\(host)")
    }

    @Test
    func smtpURL() async throws {
        // Given
        let scheme = URLScheme.smtp
        let host = "google.com"

        // When
        let baseURL = BaseURL(scheme, host: host)
        let resolved = try await resolve(baseURL)

        // Then
        #expect(resolved.request.url == "\(scheme)://\(host)")
    }

    @Test
    func imapURL() async throws {
        // Given
        let scheme = URLScheme.imap
        let host = "google.com"

        // When
        let baseURL = BaseURL(scheme, host: host)
        let resolved = try await resolve(baseURL)

        // Then
        #expect(resolved.request.url == "\(scheme)://\(host)")
    }

    @Test
    func popURL() async throws {
        // Given
        let scheme = URLScheme.pop
        let host = "google.com"

        // When
        let baseURL = BaseURL(scheme, host: host)
        let resolved = try await resolve(baseURL)

        // Then
        #expect(resolved.request.url == "\(scheme)://\(host)")
    }

    @Test
    func dnsURL() async throws {
        // Given
        let scheme = URLScheme.dns
        let host = "google.com"

        // When
        let baseURL = BaseURL(scheme, host: host)
        let resolved = try await resolve(baseURL)

        // Then
        #expect(resolved.request.url == "\(scheme)://\(host)")
    }

    @Test
    func sshURL() async throws {
        // Given
        let scheme = URLScheme.ssh
        let host = "google.com"

        // When
        let baseURL = BaseURL(scheme, host: host)
        let resolved = try await resolve(baseURL)

        // Then
        #expect(resolved.request.url == "\(scheme)://\(host)")
    }

    @Test
    func telnetURL() async throws {
        // Given
        let scheme = URLScheme.telnet
        let host = "google.com"

        // When
        let baseURL = BaseURL(scheme, host: host)
        let resolved = try await resolve(baseURL)

        // Then
        #expect(resolved.request.url == "\(scheme)://\(host)")
    }

    @Test
    func defaultURLWithoutProtocol() async throws {
        // Given
        let host = "google.com.br"

        // When
        let baseURL = BaseURL(host)
        let resolved = try await resolve(baseURL)

        // Then
        #expect(resolved.request.url == "https://google.com.br")
    }

    @Test
    func collisionBaseURL() async throws {
        // Given
        let host1 = "apple.com"
        let host2 = "google.com"

        // When
        let resolved = try await resolve(TestProperty {
            BaseURL(.ftp, host: host1)
            BaseURL(host2)
        })

        // Then
        #expect(resolved.request.url == "https://google.com")
    }

    @Test
    func url_whenIncludingScheme() async throws {
        // Given
        let baseURL = "https://www.apple.com"

        do {
            // When
            _ = try await resolve(TestProperty {
                BaseURL(baseURL)
            })

            // Then
            Issue.record("Not expecting success")
        } catch let error as BaseURLError {
            #expect(error.context == .invalidHost)
            #expect(error.baseURL == baseURL)
            #expect(error.errorDescription == """
                Invalid host string: The url scheme should not be \
                included; BaseURL: \(baseURL)
                """
            )
        } catch {
            throw error
        }
    }

    @Test
    func url_whenEmptyString() async throws {
        // Given
        let baseURL = ""

        do {
            // When
            _ = try await resolve(TestProperty {
                BaseURL(baseURL)
            })

            // Then
            Issue.record("Not expecting success")
        } catch let error as EndpointError {
            #expect(error.context == .invalidHost)
            #expect(error.url == baseURL)
        } catch {
            throw error
        }
    }

    @Test
    func neverBody() async throws {
        // Given
        let property = BaseURL("apple.com")

        // Then
        try await assertNever(property.body)
    }
}
