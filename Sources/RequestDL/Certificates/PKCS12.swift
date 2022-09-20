import Foundation

public struct PKCS12 {

    let label: String?
    let keyID: Data?
    let trust: SecTrust?
    let certChain: [SecTrust]?
    let identity: SecIdentity?

    public init?(_ data: Data, password: String) {
        let importPasswordOption = [kSecImportExportPassphrase as NSString: password]
        var items: CFArray?
        let secError = SecPKCS12Import(data as CFData, importPasswordOption as CFDictionary, &items)

        guard
            secError == errSecSuccess,
            let items = items,
            let dictionary = items as? [[String: AnyObject]]
        else {
            if secError == errSecAuthFailed {
                #if DEBUG
                print("[Request] - ERROR: SecPKCS12Import returned errSecAuthFailed. Incorrect password?")
                #endif
            }

            return nil
        }

        self.label = Self.key(kSecImportItemLabel, in: dictionary)
        self.keyID = Self.key(kSecImportItemKeyID, in: dictionary)
        self.trust = Self.key(kSecImportItemTrust, in: dictionary)
        self.certChain = Self.key(kSecImportItemCertChain, in: dictionary)
        self.identity = Self.key(kSecImportItemIdentity, in: dictionary)
    }

    static func key<T>(_ key: CFString, in dictionary: [[String: AnyObject]]) -> T? {
        for item in dictionary {
            if let value = item[key as String] as? T {
                return value
            }

            if key == kSecImportItemLabel || key == kSecImportItemKeyID {
                var cert: SecCertificate?

                if let identity = item["identity"] {
                    // swiftlint:disable force_cast
                    let secIdentity = identity as! SecIdentity
                    SecIdentityCopyCertificate(secIdentity, &cert)

                    if let certData = cert {
                        if key == kSecImportItemLabel {
                            let summary = SecCertificateCopySubjectSummary(certData)
                            if let summary = summary {
                                return summary as? T
                            }
                        }

                        var key: SecKey?
                        SecIdentityCopyPrivateKey(secIdentity, &key)

                        if let keyData = key {
                            let attributes = SecKeyCopyAttributes(keyData)
                            if let attributes = attributes, let value = (attributes as NSDictionary)["v_Data"] as? NSData {
                                return value as? T
                            }
                        }
                    }
                }
            }
        }

        return nil
    }
}
