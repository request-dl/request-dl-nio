/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension SecCertificate {

    var data: Data? {
        let data = SecCertificateCopyData(self)

        guard let serverCertificateRawPointer = CFDataGetBytePtr(data) else {
            return nil
        }

        return Data(
            bytes: serverCertificateRawPointer,
            count: CFDataGetLength(data)
        )
    }
}
