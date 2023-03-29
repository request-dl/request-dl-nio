/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDLInternals
@testable import RequestDL

class CertificatesTests: XCTestCase {

    func testCertificates_whenInit_shouldBeValid() async throws {
        // Given
        let certificate1 = RequestDLInternals.Certificates(.pem).client()
        let certificate2 = RequestDLInternals.Certificates(.der).server()

        let bytes2 = try Array(Data(contentsOf: certificate2.certificateURL))

        // When
        let (session, _) = try await resolve(TestProperty {
            RequestDL.SecureConnection {
                RequestDL.Certificates {
                    RequestDL.Certificate(certificate1.certificateURL.absolutePath())
                    RequestDL.Certificate(bytes2, format: .der)
                }
            }
        })

        // Then
        XCTAssertEqual(
            session.configuration.secureConnection?.certificateChain,
            .init([
                .file(certificate1.certificateURL.absolutePath()),
                .certificate(.init(bytes2, format: .der))
            ])
        )
    }

    func testCertificates_whenAccessBody_shouldBeNever() async throws {
        // Given
        let sut = RequestDL.Certificates {
            RequestDL.Certificate([0, 1, 2])
        }

        // Then
        try await assertNever(sut.body)
    }
}
