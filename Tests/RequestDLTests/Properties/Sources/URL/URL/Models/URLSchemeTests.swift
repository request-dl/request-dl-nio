/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct URLSchemeTests {

    @Test
    func httpRawValue() async throws {
        #expect(URLScheme.http == "http")
    }

    @Test
    func httpsRawValue() async throws {
        #expect(URLScheme.https == "https")
    }

    @Test
    func ftpRawValue() async throws {
        #expect(URLScheme.ftp == "ftp")
    }

    @Test
    func smtpRawValue() async throws {
        #expect(URLScheme.smtp == "smtp")
    }

    @Test
    func imapRawValue() async throws {
        #expect(URLScheme.imap == "imap")
    }

    @Test
    func popRawValue() async throws {
        #expect(URLScheme.pop == "pop")
    }

    @Test
    func dnsRawValue() async throws {
        #expect(URLScheme.dns == "dns")
    }

    @Test
    func sshRawValue() async throws {
        #expect(URLScheme.ssh == "ssh")
    }

    @Test
    func telnetRawValue() async throws {
        #expect(URLScheme.telnet == "telnet")
    }

    @Test
    func scheme_withStringLossless() async throws {
        // Given
        let scheme = URLScheme.dns

        // When
        let string = String(scheme)
        let losslessScheme = URLScheme(string)

        // Then
        #expect(string == scheme.description)
        #expect(losslessScheme == scheme)
    }
}
