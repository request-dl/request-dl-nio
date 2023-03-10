/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct PKCS12Certificate {

    typealias Dictionary = [AnyHashable: Any]

    let id: Data
    let trust: SecTrust
    let identity: SecIdentity
    let chain: [SecTrust]
    let subjects: [AnyHashable: String]

    fileprivate init(
        id: Data,
        trust: SecTrust,
        identity: SecIdentity,
        chain: [SecTrust],
        subjects: [AnyHashable: String]
    ) {
        self.id = id
        self.trust = trust
        self.identity = identity
        self.chain = chain
        self.subjects = subjects
    }
}

extension PKCS12Certificate {

    // swiftlint:disable force_cast
    init?(from dictionary: Dictionary) {
        var dictionary = dictionary
        guard
            let id = dictionary.removeValue(forKey: kSecImportItemKeyID) as? Data,
            let trust = dictionary.removeValue(forKey: kSecImportItemTrust),
            let identity = dictionary.removeValue(forKey: kSecImportItemIdentity),
            let chain = dictionary.removeValue(forKey: kSecImportItemCertChain) as? [SecTrust]
        else { return nil }

        self = .init(
            id: id,
            trust: trust as! SecTrust,
            identity: identity as! SecIdentity,
            chain: chain,
            subjects: dictionary.compactMapValues { "\($0)" }
        )
    }
}
