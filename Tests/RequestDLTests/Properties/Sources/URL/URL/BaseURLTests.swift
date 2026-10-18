//
// See LICENSE for this package's licensing information.
//

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
        #expect(resolved.requestConfiguration.url == "\(scheme)://\(host)")
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
        #expect(resolved.requestConfiguration.url == "\(scheme)://\(host)")
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
        #expect(resolved.requestConfiguration.url == "\(scheme)://\(host)")
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
        #expect(resolved.requestConfiguration.url == "\(scheme)://\(host)")
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
        #expect(resolved.requestConfiguration.url == "\(scheme)://\(host)")
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
        #expect(resolved.requestConfiguration.url == "\(scheme)://\(host)")
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
        #expect(resolved.requestConfiguration.url == "\(scheme)://\(host)")
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
        #expect(resolved.requestConfiguration.url == "\(scheme)://\(host)")
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
        #expect(resolved.requestConfiguration.url == "\(scheme)://\(host)")
    }

    @Test
    func defaultURLWithoutProtocol() async throws {
        // Given
        let host = "google.com.br"

        // When
        let baseURL = BaseURL(host)
        let resolved = try await resolve(baseURL)

        // Then
        #expect(resolved.requestConfiguration.url == "https://google.com.br")
    }

    @Test
    func collisionBaseURL() async throws {
        // Given
        let host1 = "apple.com"
        let host2 = "google.com"

        // When
        let resolved = try await resolve(
            TestProperty {
                BaseURL(.ftp, host: host1)
                BaseURL(host2)
            }
        )

        // Then
        #expect(resolved.requestConfiguration.url == "https://google.com")
    }

    @Test
    func url_whenIncludingScheme() async throws {
        // Given
        let baseURL = "https://www.apple.com"

        do {
            // When
            _ = try await resolve(
                TestProperty {
                    BaseURL(baseURL)
                }
            )

            // Then
            Issue.record("Not expecting success")
        } catch let error as BaseURLError {
            #expect(error.context == .invalidHost)
            #expect(error.baseURL == baseURL)
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
            _ = try await resolve(
                TestProperty {
                    BaseURL(baseURL)
                }
            )

            // Then
            Issue.record("Not expecting success")
        } catch let error as BaseURLError {
            #expect(error.context == .unexpectedHost)
            #expect(error.baseURL == baseURL)
        } catch {
            throw error
        }
    }

    @Test
    func url_whenHostContainsAPath_throwsUnexpectedHostInsteadOfTruncating() async throws {
        // Given
        let baseURL = "apple.com/api/v1"

        do {
            // When
            _ = try await resolve(
                TestProperty {
                    BaseURL(baseURL)
                }
            )

            // Then
            Issue.record("Not expecting success")
        } catch let error as BaseURLError {
            #expect(error.context == .unexpectedHost)
            #expect(error.baseURL == baseURL)
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

    // MARK: - User info

    /// Same as `FlexibleURL`: a user name or a password in the host would not be sent and would
    /// end up in logs, and the error does not repeat them.
    @Test(arguments: [
        ("user:password@example.com", "REDACTED@example.com"),
        ("user@example.com:8443", "REDACTED@example.com:8443"),
        ("https://user:password@example.com", "https://REDACTED@example.com"),
        ("user:password@example.com/path", "REDACTED@example.com/path"),
    ])
    func host_whenItHasUserInfo_throwsUserInfoNotAllowed(
        _ host: String,
        _ expected: String
    ) async {
        // When
        let error = await #expect(throws: BaseURLError.self) {
            try await resolve(TestProperty { BaseURL(host) })
        }

        // Then
        #expect(error?.context == .userInfoNotAllowed)
        #expect(error?.baseURL == expected)
    }

    @Test(arguments: ["example.com", "example.com:8443", "[::1]:8080"])
    func host_whenItHasNoUserInfo_isAccepted(_ host: String) async throws {
        // When
        let resolved = try await resolve(TestProperty { BaseURL(host) })

        // Then
        #expect(resolved.requestConfiguration.url == "https://\(host)")
    }
}
