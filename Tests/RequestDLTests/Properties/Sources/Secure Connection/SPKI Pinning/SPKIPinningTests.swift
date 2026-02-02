/*
 See LICENSE for this package's licensing information.
*/

import Testing
@testable import RequestDL

struct SPKIPinningTests {

    @Test
    func pinning() async throws {
        _ = try await DataTask {
            BaseURL(.https, host: "www.google.com")
            SecureConnection {
                SPKIPinning {
                    SPKIActivePins {
                        SPKIHash("dJEGUdm2BuEalPybF+8enWB7R4AeiwE0gsQHyQrhzhY=")
                    }
                }
            }
        }
        .result()
    }
}
