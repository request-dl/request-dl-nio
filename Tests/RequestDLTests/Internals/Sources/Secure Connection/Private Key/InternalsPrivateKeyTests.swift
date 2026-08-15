//
// See LICENSE for this package's licensing information.
//

import NIOSSL
import Testing

@testable import RequestDL

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

struct InternalsPrivateKeyTests {

    @Test
    func private_whenPEM_shouldBeValid() async throws {
        // Given
        let certificates = Certificates().client()
        let data = try Data(contentsOf: certificates.privateKeyURL)

        // When
        let resolved = try Internals.PrivateKey(Array(data), format: .pem).build()

        // Then
        let expectedPrivateKey = try NIOSSLPrivateKey(bytes: Array(data), format: .pem)
        #expect(resolved == expectedPrivateKey)
    }

    @Test
    func private_whenDER_shouldBeValid() async throws {
        // Given
        let certificates = Certificates(.der).client()

        let data = try Data(contentsOf: certificates.privateKeyURL)

        // When
        let resolved = try Internals.PrivateKey(Array(data), format: .der).build()

        // Then
        let expectedPrivateKey = try NIOSSLPrivateKey(bytes: Array(data), format: .der)
        #expect(resolved == expectedPrivateKey)
    }

    @Test
    func private_whenPEMWithPassword_shouldBeValid() async throws {
        // Given
        let password = NIOSSLSecureBytes("password123".utf8)
        let certificates = Certificates().client(password: true)

        let data = try Data(contentsOf: certificates.privateKeyURL)

        // When
        let resolved = try Internals.PrivateKey(
            Array(data),
            format: .pem,
            password: password
        ).build()

        // Then
        let expectedPrivateKey = try NIOSSLPrivateKey(bytes: Array(data), format: .pem) {
            $0(password)
        }
        #expect(resolved == expectedPrivateKey)
    }

    @Test
    func private_whenDERWithPassword_shouldBeValid() async throws {
        // Given
        let password = NIOSSLSecureBytes("password123".utf8)
        let certificates = Certificates(.der).client(password: true)

        let data = try Data(contentsOf: certificates.privateKeyURL)

        // When
        let resolved = try Internals.PrivateKey(
            Array(data),
            format: .der,
            password: password
        ).build()

        // Then
        let expectedPrivateKey = try NIOSSLPrivateKey(bytes: Array(data), format: .der) {
            $0(password)
        }
        #expect(resolved == expectedPrivateKey)
    }

    @Test
    func private_whenPEMFile_shouldBeValid() async throws {
        // Given
        let certificates = Certificates().client()
        let file = certificates.privateKeyURL.absolutePath(percentEncoded: false)

        // When
        let resolved = try Internals.PrivateKey(file, format: .pem).build()

        // Then
        let expectedPrivateKey = try NIOSSLPrivateKey(file: file, format: .pem)
        #expect(resolved == expectedPrivateKey)
    }

    @Test
    func private_whenDERFile_shouldBeValid() async throws {
        // Given
        let certificates = Certificates(.der).client()

        let file = certificates.privateKeyURL.absolutePath(percentEncoded: false)

        // When
        let resolved = try Internals.PrivateKey(file, format: .der).build()

        // Then
        let expectedPrivateKey = try NIOSSLPrivateKey(file: file, format: .der)
        #expect(resolved == expectedPrivateKey)
    }

    @Test
    func private_whenPEMFileWithPassword_shouldBeValid() async throws {
        // Given
        let password = NIOSSLSecureBytes("password123".utf8)
        let certificates = Certificates().client(password: true)
        let file = certificates.privateKeyURL.absolutePath(percentEncoded: false)

        // When
        let resolved = try Internals.PrivateKey(
            file,
            format: .pem,
            password: password
        ).build()

        // Then
        let expectedPrivateKey = try NIOSSLPrivateKey(file: file, format: .pem) {
            $0(password)
        }
        #expect(resolved == expectedPrivateKey)
    }

    @Test
    func private_whenDERFileWithPassword_shouldBeValid() async throws {
        // Given
        let password = NIOSSLSecureBytes("password123".utf8)
        let certificates = Certificates(.der).client(password: true)
        let file = certificates.privateKeyURL.absolutePath(percentEncoded: false)

        // When
        let resolved = try Internals.PrivateKey(
            file,
            format: .der,
            password: password
        ).build()

        // Then
        let expectedPrivateKey = try NIOSSLPrivateKey(file: file, format: .der) {
            $0(password)
        }
        #expect(resolved == expectedPrivateKey)
    }

    @Test
    func private_whenFileDoesNotExist_shouldThrowSecureFileErrorWithPath() async throws {
        try await withTemporaryFileURL("missing.pem", createPath: false) { url in
            // Given
            let path = url.absolutePath(percentEncoded: false)

            // When
            do {
                _ = try Internals.PrivateKey(path, format: .pem).build()
                Issue.record("Not expecting success")
            } catch let error as SecureFileError {
                // Then
                #expect(error.resource == .privateKey)
                #expect(error.path == path)
                #expect(error.isRelativePath == false)

                guard case .cantOpenFile = error.context else {
                    Issue.record("Expected .cantOpenFile, got \(error.context)")
                    return
                }
            }
        }
    }

    @Test
    func private_whenRelativePathDoesNotExist_shouldReportRelativePath() async throws {
        // Given
        let path = "definitely-not-a-real-private-key.pem"

        // When
        do {
            _ = try Internals.PrivateKey(path, format: .pem).build()
            Issue.record("Not expecting success")
        } catch let error as SecureFileError {
            // Then
            #expect(error.isRelativePath == true)
        }
    }

    // MARK: - Genuinely encrypted key (passphrase closure actually invoked)

    /// Unlike the bundled `client_password` fixture, this key is genuinely passphrase
    /// encrypted (`Proc-Type: 4,ENCRYPTED` / `DEK-Info`), so NIOSSL actually has to call the
    /// passphrase closure to decrypt it. The bundled fixture's "password" variant is a
    /// plaintext PKCS#1 key that happens to parse fine without ever invoking the callback,
    /// which is why `build()`'s two passphrase-closure bodies never ran under the tests above.
    private static let genuinelyEncryptedPEMKey = """
        -----BEGIN RSA PRIVATE KEY-----
        Proc-Type: 4,ENCRYPTED
        DEK-Info: AES-256-CBC,7FF776C4810408D1267DBB1820D26214

        v7+883l1XRxSbkoPYce916qOG8XRRz/YCCsBNodZXHLQ9rsTkAzAPmZ2I5vez5Rj
        ufNiEJD483xvQtWm4MTEbDKe9rs/ry0wYUUtcqgBbz2zfd2u1w5jm/dkcg24TdX7
        81jkEbDmkemCAy/LleVXRRWIuNuTdHqQT9QrMsHx8dw0xqnht7RxO3OlTANGT+yD
        ++IhRH/Q8fWDmnqkqb0GGFWh+4tPBPCedjIlB3Xo35/O1MYuY2MDH9PYXnVF8PjX
        G6H4kNuS6yZxmqO2jlAH7A6QC9+2DzTo6deXLp+352Jmun1sAmDW164MSuBL3HVU
        FPyxG+CloHvHeg96CE5ALZR02ueYJF8Y3ihI1pnxDRYB4kYuVASuDmx1foryFI7n
        X2Q86dUEU579Fa9+SpiJIeMG6A7YqI+LuQT/OS3oBDkBjpri9O5y7TfG2/6b0Ucq
        bPFLHgEbRha2JJbNPKAIY4YGOvmN+3syBlAdtqfd5cnYraXRZJcYaqvsOuJOFLRY
        bzusYGzFldKEqm4CwAk4wpOMXHaJn3fC25fXsoowSNV8OeXNo3U5RyzdT2wUn1gc
        LTNITqeLXsr4WPTzUPd5vqc6UKyK2f/ui2uXFGKlrDcWx6yZoA/vL2STSO/fM2ed
        DR6F4+TzQlMqy0S1zBuTZ4TECpJV5BAlSQkOGK0TzxxfhmTbA/TU7SfW9UFAZfTd
        rggAAHJ8XTmQoyPeS/Zt+oCy3ZOftUgqnKXuoFMMnKsAsCeSjof7Y2hqlBcAOFGv
        LmSbszEez5NwpoMC9temSr8CbNfqb3aXIA4X6JpZY8sV+JZxit5GQVSOzfcZi6tD
        TkWndrMVqGZifD+Y38ok8SdvZlIHbeS/8dIh/sbl12J+c4Zjg856rwL4OCjQaq3e
        ZdlAh4ynV23fs5z6KcMPvtyLJdb9d58gLUmufgD+F8Yfn8cSq0MhRHKxqO6Dbs1V
        ApbYECVDyJuRmv5xTMqa7SGeEC1uYY9ASfzkxM0O9Gp4Si7gYIIkiMsBm1BsBgFg
        0ZkrNiVA0wM7N+J0v96C8iBVbE1cw96yAka5F7vPOzHCfo2C/cvSEP90affjwcRk
        bh3w7DClJ4tqduNmfT9TFTZNmlCajiSJPuZet9E5MYBz8BMb4CI+49M6LY2fgitz
        skVwBU/j+yNj2M+WaRS8dboTEhDsj72G6pSEh0HXD80f/EKgdB2ARykASK21hTVw
        KG8zD6Gq3m1u2kCKjHauCgrO9KH1KzrMbouSYcJPYTo26TzVHMs3gasjyVV2f7cg
        mj3JvEqPHJauFcoel7c4NRX7NokLbNPULvAyoPLqoJ3tvUxpmEY1Bril9mO0XyT+
        +s7vDVEIBqKJLCHdbHqE8jghzV/WS0i/citSQjrZHNlj/GCFXFIjWmzRdmS1aTeR
        FJ9TrnaCbwjONa5UEm6iyARhzp3oHadhkWN0qeWo4sWn8f98EMm1+C7CG5gQUN9S
        KnSOatWbWIoPqYMgmw+CcVbA5uZweEYeJ/Jd0eVvukulWoxC84j+xUOs0Ts6ovJR
        6qtnePvAea0snCejo9DNiMoRGJ9c6hQWa+mE2RQvYgzo/wPaFaulMgskSqTPz6m3
        -----END RSA PRIVATE KEY-----
        """

    private static let genuinelyEncryptedPEMPassword = NIOSSLSecureBytes("testpassword123".utf8)

    @Test
    func private_whenGenuinelyEncryptedPEMBytesWithPassword_invokesPassphraseClosure() throws {
        // Given
        let bytes = Array(Self.genuinelyEncryptedPEMKey.utf8)
        let password = Self.genuinelyEncryptedPEMPassword

        // When
        let resolved = try Internals.PrivateKey(bytes, format: .pem, password: password).build()

        // Then
        let expectedPrivateKey = try NIOSSLPrivateKey(bytes: bytes, format: .pem) {
            $0(password)
        }
        #expect(resolved == expectedPrivateKey)
    }

    @Test
    func private_whenGenuinelyEncryptedPEMFileWithPassword_invokesPassphraseClosure() async throws {
        let password = Self.genuinelyEncryptedPEMPassword

        try await withTemporaryFileURL("encrypted_key.pem") { url in
            // Given
            try await url.write(Data(Self.genuinelyEncryptedPEMKey.utf8))
            let file = url.absolutePath(percentEncoded: false)

            // When
            let resolved = try Internals.PrivateKey(file, format: .pem, password: password).build()

            // Then
            let expectedPrivateKey = try NIOSSLPrivateKey(file: file, format: .pem) {
                $0(password)
            }
            #expect(resolved == expectedPrivateKey)
        }
    }
}
