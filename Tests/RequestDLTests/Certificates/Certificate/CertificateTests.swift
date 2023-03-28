/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDLInternals
@testable import RequestDL

class CertificateTests: XCTestCase {

    func testCertificate_whenClientPEMFile_shouldBeValid() async throws {
        // Given
        let resource = RequestDLInternals.Certificates(.pem).client()
        let file = resource.certificateURL.absolutePath()

        let certificate = RequestDL.Certificate(
            file,
            format: .pem
        )

        // When
        let (session, _) = try await resolve(TestProperty {
            SecureConnection {
                certificate
            }
        })

        // Then
        XCTAssertEqual(
            session.configuration.secureConnection?.additionalTrustRoots,
            .init([.file(file)])
        )
    }

    func testCertificate_whenClientDERFile_shouldBeValid() async throws {
        // Given
        let resource = RequestDLInternals.Certificates(.der).client()
        let file = resource.certificateURL.absolutePath()

        let certificate = RequestDL.Certificate(
            file,
            format: .der
        )

        // When
        let (session, _) = try await resolve(TestProperty {
            SecureConnection {
                certificate
            }
        })

        // Then
        XCTAssertEqual(
            session.configuration.secureConnection?.additionalTrustRoots,
            .init([.certificate(.certificate(.init(file, format: .der)))])
        )
    }

    func testCertificate_whenClientPEMBytes_shouldBeValid() async throws {
        // Given
        let resource = RequestDLInternals.Certificates(.pem).client()
        let file = resource.certificateURL
        let bytes = try Array(Data(contentsOf: file))

        let certificate = RequestDL.Certificate(
            bytes,
            format: .pem
        )

        // When
        let (session, _) = try await resolve(TestProperty {
            SecureConnection {
                certificate
            }
        })

        // Then
        XCTAssertEqual(
            session.configuration.secureConnection?.additionalTrustRoots,
            .init([.certificate(.bytes(bytes))])
        )
    }

    func testCertificate_whenClientDERBytes_shouldBeValid() async throws {
        // Given
        let resource = RequestDLInternals.Certificates(.der).client()
        let file = resource.certificateURL
        let bytes = try Array(Data(contentsOf: file))

        let certificate = RequestDL.Certificate(
            bytes,
            format: .der
        )

        // When
        let (session, _) = try await resolve(TestProperty {
            SecureConnection {
                certificate
            }
        })

        // Then
        XCTAssertEqual(
            session.configuration.secureConnection?.additionalTrustRoots,
            .init([.certificate(.certificate(.init(bytes, format: .der)))])
        )
    }

    func testCertificate_whenServerPEMFile_shouldBeValid() async throws {
        // Given
        let resource = RequestDLInternals.Certificates(.pem).client()
        let file = resource.certificateURL.absolutePath()

        let certificate = RequestDL.Certificate(
            file,
            format: .pem
        )

        // When
        let (session, _) = try await resolve(TestProperty {
            SecureConnection(.server) {
                certificate
            }
        })

        // Then
        XCTAssertEqual(
            session.configuration.secureConnection?.certificateChain,
            .init([.file(file)])
        )
    }

    func testCertificate_whenServerDERFile_shouldBeValid() async throws {
        // Given
        let resource = RequestDLInternals.Certificates(.der).server()
        let file = resource.certificateURL.absolutePath()

        let certificate = RequestDL.Certificate(
            file,
            format: .der
        )

        // When
        let (session, _) = try await resolve(TestProperty {
            SecureConnection(.server) {
                certificate
            }
        })

        // Then
        XCTAssertEqual(
            session.configuration.secureConnection?.certificateChain,
            .init([.certificate(.init(file, format: .der))])
        )
    }

    func testCertificate_whenServerPEMBytes_shouldBeValid() async throws {
        // Given
        let resource = RequestDLInternals.Certificates(.pem).server()
        let file = resource.certificateURL
        let bytes = try Array(Data(contentsOf: file))

        let certificate = RequestDL.Certificate(
            bytes,
            format: .pem
        )

        // When
        let (session, _) = try await resolve(TestProperty {
            SecureConnection(.server) {
                certificate
            }
        })

        // Then
        XCTAssertEqual(
            session.configuration.secureConnection?.certificateChain,
            .init([.bytes(bytes)])
        )
    }

    func testCertificate_whenServerDERBytes_shouldBeValid() async throws {
        // Given
        let resource = RequestDLInternals.Certificates(.der).server()
        let file = resource.certificateURL
        let bytes = try Array(Data(contentsOf: file))

        let certificate = RequestDL.Certificate(
            bytes,
            format: .der
        )

        // When
        let (session, _) = try await resolve(TestProperty {
            SecureConnection(.server) {
                certificate
            }
        })

        // Then
        XCTAssertEqual(
            session.configuration.secureConnection?.certificateChain,
            .init([.certificate(.init(bytes, format: .der))])
        )
    }
}
