//
//  File.swift
//
//
//  Created by Brenno on 06/03/23.
//

import Foundation

extension SecTrust {

    var certificates: [SecCertificate] {
        if #available(iOS 15, macOS 12, tvOS 15, watchOS 8, *) {
            return SecTrustCopyCertificateChain(self) as? [SecCertificate] ?? []
        }

        var error: CFError?

        guard
            SecTrustEvaluateWithError(self, &error),
            error == nil
        else { return [] }

        var certificates = [SecCertificate]()

        for index in 0 ..< .max {
            guard let certificate = SecTrustGetCertificateAtIndex(self, index) else {
                break
            }

            certificates.append(certificate)
        }

        return certificates
    }
}
