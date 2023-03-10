/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension SecCertificate {

    var data: Data? {
        let data = SecCertificateCopyData(self)

        return CFDataGetBytePtr(data).map {
            Data(
                bytes: $0,
                count: CFDataGetLength(data)
            )
        }
    }
}
