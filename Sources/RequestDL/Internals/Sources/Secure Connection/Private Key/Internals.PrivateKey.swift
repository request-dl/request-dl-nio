/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOSSL

extension Internals {
    
    struct PrivateKey<Password: Collection> where Password.Element == UInt8 {

        typealias PasswordClosure = ((Password) -> Void) throws -> Void

        enum Source: Equatable {
            case file(String)
            case bytes([UInt8])
        }

        let source: Source
        let format: Internals.Certificate.Format
        let password: PasswordClosure?

        init(_ file: String, format: Internals.Certificate.Format) where Password == [UInt8] {
            self.source = .file(file)
            self.format = format
            self.password = nil
        }

        init(_ bytes: [UInt8], format: Internals.Certificate.Format) where Password == [UInt8] {
            self.source = .bytes(bytes)
            self.format = format
            self.password = nil
        }

        init(_ file: String, format: Internals.Certificate.Format, password: @escaping PasswordClosure) {
            self.source = .file(file)
            self.format = format
            self.password = password
        }

        init(_ bytes: [UInt8], format: Internals.Certificate.Format, password: @escaping PasswordClosure) {
            self.source = .bytes(bytes)
            self.format = format
            self.password = password
        }
    }
}

extension Internals.PrivateKey: PrivateKeyRepresentable {

    func build() throws -> NIOSSLPrivateKey {
        let format = format.build()

        switch source {
        case .bytes(let bytes):
            if let password {
                return try .init(bytes: bytes, format: format, passphraseCallback: password)
            } else {
                return try .init(bytes: bytes, format: format)
            }
        case .file(let file):
            if let password {
                return try .init(file: file, format: format, passphraseCallback: password)
            } else {
                return try .init(file: file, format: format)
            }
        }
    }

    func isEqual(to representable: PrivateKeyRepresentable) -> Bool {
        guard
            let lhs = try? build(),
            let rhs = try? representable.build()
        else { return false }

        return lhs == rhs
    }
}
