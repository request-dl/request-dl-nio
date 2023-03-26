/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import RequestDLInternals

public struct PrivateKey<Password: Collection>: Property where Password.Element == UInt8 {

    fileprivate enum Source {
        case file(String)
        case privateKey(RequestDLInternals.PrivateKey<Password>)
    }

    private let source: Source

    private init(_ source: Source) {
        self.source = source
    }

    public init(_ file: String, format: CertificateFormat = .pem) where Password == [UInt8] {
        switch format {
        case .pem:
            self.init(.file(file))
        case .der:
            self.init(.privateKey(.init(file, format: format)))
        }
    }

    public init(_ bytes: [UInt8], format: CertificateFormat = .pem) where Password == [UInt8] {
        self.init(.privateKey(.init(
            bytes,
            format: format
        )))
    }

    public init(
        _ file: String,
        format: CertificateFormat = .pem,
        password: @escaping ((Password) -> Void) -> Void
    ) {
        self.init(.privateKey(.init(
            file,
            format: format,
            password: password
        )))
    }

    public init(
        _ bytes: [UInt8],
        format: CertificateFormat = .pem,
        password: @escaping ((Password) -> Void) -> Void
    ) {
        self.init(.privateKey(.init(
            bytes,
            format: format,
            password: password
        )))
    }

    public var body: Never {
        bodyException()
    }
}

extension PrivateKey: PrimitiveProperty {

    func makeObject() -> SecureConnectionNode {
        SecureConnectionNode {
            switch source {
            case .file(let file):
                $0.privateKey = .file(file)
            case .privateKey(let privateKey):
                $0.privateKey = .privateKey(privateKey)
            }
        }
    }
}
