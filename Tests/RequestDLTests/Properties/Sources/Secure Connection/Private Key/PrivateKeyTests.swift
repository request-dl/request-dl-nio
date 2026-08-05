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

#if canImport(Darwin)
import class Foundation.Bundle
#endif

struct PrivateKeyTests {

    @Test
    func privateKey_whenInitPEMFileNoPassword_shouldBeValid() async throws {
        // Given
        let resource = Certificates(.pem).client()

        // When
        let resolved = try await resolve(
            TestProperty {
                RequestDL.SecureConnection {
                    RequestDL.PrivateKey(resource.privateKeyURL.absolutePath(percentEncoded: false), format: .pem)
                }
            }
        )

        // Then
        #expect(
            resolved.session.configuration.secureConnection?.privateKey
                == .privateKey(
                    .init(resource.privateKeyURL.absolutePath(percentEncoded: false), format: .pem)
                )
        )
    }

    @Test
    func privateKey_whenInitDERFileNoPassword_shouldBeValid() async throws {
        // Given
        let resource = Certificates(.der).client()

        // When
        let resolved = try await resolve(
            TestProperty {
                RequestDL.SecureConnection {
                    RequestDL.PrivateKey(resource.privateKeyURL.absolutePath(percentEncoded: false), format: .der)
                }
            }
        )

        // Then
        #expect(
            resolved.session.configuration.secureConnection?.privateKey
                == .privateKey(
                    Internals.PrivateKey(
                        resource.privateKeyURL.absolutePath(percentEncoded: false),
                        format: .der
                    )
                )
        )
    }

    @Test
    func privateKey_whenInitPEMBytesNoPassword_shouldBeValid() async throws {
        // Given
        let resource = Certificates(.pem).client()
        let bytes = try Array(Data(contentsOf: resource.privateKeyURL))

        // When
        let resolved = try await resolve(
            TestProperty {
                RequestDL.SecureConnection {
                    RequestDL.PrivateKey(bytes, format: .pem)
                }
            }
        )

        // Then
        #expect(
            resolved.session.configuration.secureConnection?.privateKey
                == .privateKey(
                    Internals.PrivateKey(bytes, format: .pem)
                )
        )
    }

    @Test
    func privateKey_whenInitDERBytesNoPassword_shouldBeValid() async throws {
        // Given
        let resource = Certificates(.der).client()
        let bytes = try Array(Data(contentsOf: resource.privateKeyURL))

        // When
        let resolved = try await resolve(
            TestProperty {
                RequestDL.SecureConnection {
                    RequestDL.PrivateKey(bytes, format: .der)
                }
            }
        )

        // Then
        #expect(
            resolved.session.configuration.secureConnection?.privateKey
                == .privateKey(
                    Internals.PrivateKey(
                        bytes,
                        format: .der
                    )
                )
        )
    }

    // `PrivateKey(_:in:format:)` only exists on Darwin — it is built on `Bundle`, which is not
    // part of `FoundationEssentials`. This test exists to cover that initializer specifically,
    // so unlike the rest of this file, it has no portable counterpart to fall back to.
    #if canImport(Darwin)
    @Test
    func privateKey_whenInitPEMFileNoPasswordInBundle_shouldBeValid() async throws {
        // Given
        let resource = Certificates(.pem).client()

        let file = resource.privateKeyURL.lastPathComponent

        // When
        let resolved = try await resolve(
            TestProperty {
                RequestDL.SecureConnection {
                    RequestDL.PrivateKey(file, in: .module, format: .pem)
                }
            }
        )

        // Then
        #expect(
            resolved.session.configuration.secureConnection?.privateKey
                == Bundle.module.resolveURL(forResourceName: file).map {
                    .privateKey(.init($0.absolutePath(percentEncoded: false), format: .pem))
                }
        )
    }
    #endif

    @Test
    func privateKey_whenInitPEMFileWithPasswordBytes() async throws {
        // Given
        let resource = Certificates(.pem).client(password: true)
        let password = NIOSSLSecureBytes("password".utf8)

        // When
        let resolved = try await resolve(
            TestProperty {
                RequestDL.SecureConnection {
                    RequestDL.PrivateKey(
                        resource.privateKeyURL.absolutePath(percentEncoded: false),
                        format: .pem,
                        password: password
                    )
                }
            }
        )

        // Then
        #expect(
            resolved.session.configuration.secureConnection?.privateKey
                == .privateKey(
                    Internals.PrivateKey(
                        resource.privateKeyURL.absolutePath(percentEncoded: false),
                        format: .pem,
                        password: .init(password)
                    )
                )
        )
    }

    @Test
    func privateKey_whenInitDERFileWithPasswordBytes() async throws {
        // Given
        let resource = Certificates(.der).client()
        let password = NIOSSLSecureBytes("password".utf8)

        // When
        let resolved = try await resolve(
            TestProperty {
                RequestDL.SecureConnection {
                    RequestDL.PrivateKey(
                        resource.privateKeyURL.absolutePath(percentEncoded: false),
                        format: .der,
                        password: password
                    )
                }
            }
        )

        // Then
        #expect(
            resolved.session.configuration.secureConnection?.privateKey
                == .privateKey(
                    Internals.PrivateKey(
                        resource.privateKeyURL.absolutePath(percentEncoded: false),
                        format: .der,
                        password: .init(password)
                    )
                )
        )
    }

    @Test
    func privateKey_whenInitPEMBytesWithPasswordBytes() async throws {
        // Given
        let resource = Certificates(.pem).client(password: true)
        let bytes = try Array(Data(contentsOf: resource.privateKeyURL))
        let password = NIOSSLSecureBytes("password".utf8)

        // When
        let resolved = try await resolve(
            TestProperty {
                RequestDL.SecureConnection {
                    RequestDL.PrivateKey(
                        bytes,
                        format: .pem,
                        password: password
                    )
                }
            }
        )

        // Then
        #expect(
            resolved.session.configuration.secureConnection?.privateKey
                == .privateKey(
                    Internals.PrivateKey(
                        bytes,
                        format: .pem,
                        password: .init(password)
                    )
                )
        )
    }

    @Test
    func privateKey_whenInitDERBytesWithPasswordBytes() async throws {
        // Given
        let resource = Certificates(.der).client()
        let bytes = try Array(Data(contentsOf: resource.privateKeyURL))
        let password = NIOSSLSecureBytes("password".utf8)

        // When
        let resolved = try await resolve(
            TestProperty {
                RequestDL.SecureConnection {
                    RequestDL.PrivateKey(
                        bytes,
                        format: .der,
                        password: password
                    )
                }
            }
        )

        // Then
        #expect(
            resolved.session.configuration.secureConnection?.privateKey
                == .privateKey(
                    Internals.PrivateKey(
                        bytes,
                        format: .der,
                        password: .init(password)
                    )
                )
        )
    }

    // Same reason as ``privateKey_whenInitPEMFileNoPasswordInBundle_shouldBeValid()`` above.
    #if canImport(Darwin)
    @Test
    func privateKey_whenInitPEMFileWithPasswordBytesInBundle() async throws {
        // Given
        let resource = Certificates(.pem).client(password: true)
        let password = NIOSSLSecureBytes("password".utf8)

        let file = resource.privateKeyURL.lastPathComponent

        // When
        let resolved = try await resolve(
            TestProperty {
                RequestDL.SecureConnection {
                    RequestDL.PrivateKey(
                        file,
                        in: .module,
                        format: .pem,
                        password: password
                    )
                }
            }
        )

        // Then
        #expect(
            resolved.session.configuration.secureConnection?.privateKey
                == Bundle.module.resolveURL(forResourceName: file).map {
                    .privateKey(
                        Internals.PrivateKey(
                            $0.absolutePath(percentEncoded: false),
                            format: .pem,
                            password: .init(password)
                        )
                    )
                }
        )
    }
    #endif

    @Test
    func certificate_whenAccessBody_shouldBeNever() async throws {
        // Given
        let resource = Certificates(.pem).client()

        // Wehn
        let sut = RequestDL.PrivateKey(resource.privateKeyURL.absolutePath(percentEncoded: false))

        // Then
        try await assertNever(sut.body)
    }
}
