/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDLInternals
@testable import RequestDL

class TrustsTests: XCTestCase {

    func testCertificates_whenInitDefault_shouldBeValid() async throws {
        // Given
        let certificate1 = RequestDLInternals.Certificates(.pem).client()
        let certificate2 = RequestDLInternals.Certificates(.der).server()

        let bytes2 = try Array(Data(contentsOf: certificate2.certificateURL))

        // When
        let (session, _) = try await resolve(TestProperty {
            RequestDL.SecureConnection {
                RequestDL.Trusts(.default) {
                    RequestDL.Certificate(certificate1.certificateURL.absolutePath())
                    RequestDL.Certificate(bytes2, format: .der)
                }
            }
        })

        // Then
        XCTAssertEqual(
            session.configuration.secureConnection?.trustRoots,
            .default
        )

        XCTAssertEqual(
            session.configuration.secureConnection?.additionalTrustRoots,
            .init([
                .file(certificate1.certificateURL.absolutePath()),
                .certificate(.certificate(.init(bytes2, format: .der)))
            ])
        )
    }

    func testCertificates_whenInit_shouldBeValid() async throws {
        // Given
        let certificate1 = RequestDLInternals.Certificates(.pem).client()
        let certificate2 = RequestDLInternals.Certificates(.der).server()

        let bytes2 = try Array(Data(contentsOf: certificate2.certificateURL))

        // When
        let (session, _) = try await resolve(TestProperty {
            RequestDL.SecureConnection {
                RequestDL.Trusts {
                    RequestDL.Certificate(certificate1.certificateURL.absolutePath())
                    RequestDL.Certificate(bytes2, format: .der)
                }
            }
        })

        // Then
        XCTAssertEqual(
            session.configuration.secureConnection?.trustRoots,
            .file(certificate1.certificateURL.absolutePath())
        )

        XCTAssertEqual(
            session.configuration.secureConnection?.additionalTrustRoots,
            .init([
                .certificate(.certificate(.init(bytes2, format: .der)))
            ])
        )
    }
}
