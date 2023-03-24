/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct PKCS12Descriptor {

    let certificates: [PKCS12Certificate]

    fileprivate init(certificates: [PKCS12Certificate]) {
        self.certificates = certificates
    }
}

extension PKCS12Descriptor {

    init?(_ data: Data, password: String? = nil) {
        var chain: CFArray?

        let secError = SecPKCS12Import(
            data as CFData,
            (password.map { [kSecImportExportPassphrase: $0] } ?? [:]) as CFDictionary,
            &chain
        )

        switch secError {
        case errSecAuthFailed:
            Self.outputWrongPassword()
            return nil
        case errSecSuccess:
            guard let chain = chain as? [PKCS12Certificate.Dictionary] else {
                return nil
            }

            self.init(certificates: chain.enumerated().compactMap {
                guard let certificate = PKCS12Certificate(from: $1) else {
                    Self.outputCertificateWrongFormat(at: $0)
                    return nil
                }

                return certificate
            })
        default:
            return nil
        }
    }
}

extension PKCS12Descriptor {

    static func outputWrongPassword() {
        #if DEBUG
        NSLog(
            "%@: %@ - %@",
            "PKCS12Chain",
            "Couldn't open the certificate (PEM)",
            "Please, verify if the  password was informed or if it is right."
        )
        #endif
    }

    static func outputCertificateWrongFormat(at index: Int) {
        #if DEBUG
        NSLog(
            "%@: %@ - %@",
            "PKCS12Chain",
            "The table of contents for the resolved certificate at index \(index) is inaccurate",
            "Kindly check the integrity of the certificate or generate a new one if necessary."
        )
        #endif
    }
}
