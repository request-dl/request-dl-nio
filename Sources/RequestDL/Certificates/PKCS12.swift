//
//  PKCS12.swift
//
//  MIT License
//
//  Copyright (c) 2022 RequestDL
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

import Foundation

struct PKCS12 {

    let label: String?
    let keyID: Data?
    let trust: SecTrust?
    let certChain: [SecTrust]?
    let identity: SecIdentity?

    init?(_ data: Data, password: String) {
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
                print("[RequestDL] - ERROR: SecPKCS12Import returned errSecAuthFailed. Incorrect password?")
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

            guard
                key == kSecImportItemLabel || key == kSecImportItemKeyID,
                let identity = item["identity"]
            else { continue }

            var cert: SecCertificate?

            // swiftlint:disable force_cast
            let secIdentity = identity as! SecIdentity
            SecIdentityCopyCertificate(secIdentity, &cert)

            guard let certData = cert else {
                continue
            }

            if key == kSecImportItemLabel {
                let summary = SecCertificateCopySubjectSummary(certData)
                if let summary = summary {
                    return summary as? T
                }
            }

            var key: SecKey?
            SecIdentityCopyPrivateKey(secIdentity, &key)

            guard
                let keyData = key,
                let attributes = SecKeyCopyAttributes(keyData),
                let value = (attributes as NSDictionary)["v_Data"] as? NSData
            else { continue }

            return value as? T
        }

        return nil
    }
}
