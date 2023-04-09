/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public struct PrivateKey<Password: Collection>: Property where Password.Element == UInt8 {

    fileprivate enum Source {
        case file(String)
        case privateKey(Internals.PrivateKey<Password>)
    }

    private let source: Source

    private init(_ source: Source) {
        self.source = source
    }

    public init(_ file: String, format: Certificate.Format = .pem) where Password == [UInt8] {
        switch format {
        case .pem:
            self.init(.file(file))
        case .der:
            self.init(.privateKey(.init(file, format: format())))
        }
    }

    public init(_ bytes: [UInt8], format: Certificate.Format = .pem) where Password == [UInt8] {
        self.init(.privateKey(.init(
            bytes,
            format: format()
        )))
    }

    public init(
        _ file: String,
        in bundle: Bundle,
        format: Certificate.Format = .pem
    ) where Password == [UInt8] {
        self.init(
            format.resolve(for: file, in: bundle),
            format: format
        )
    }

    public init(
        _ file: String,
        format: Certificate.Format = .pem,
        password: @escaping ((Password) -> Void) -> Void
    ) {
        self.init(.privateKey(.init(
            file,
            format: format(),
            password: password
        )))
    }

    public init(
        _ bytes: [UInt8],
        format: Certificate.Format = .pem,
        password: @escaping ((Password) -> Void) -> Void
    ) {
        self.init(.privateKey(.init(
            bytes,
            format: format(),
            password: password
        )))
    }

    public init(
        _ file: String,
        in bundle: Bundle,
        format: Certificate.Format = .pem,
        password: @escaping ((Password) -> Void) -> Void
    ) {
        self.init(
            format.resolve(for: file, in: bundle),
            format: format,
            password: password
        )
    }

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }
}

extension PrivateKey {

    private struct Node: SecureConnectionPropertyNode {

        let source: Source

        func make(_ secureConnection: inout Internals.SecureConnection) {
            switch source {
            case .file(let file):
                secureConnection.privateKey = .file(file)
            case .privateKey(let privateKey):
                secureConnection.privateKey = .privateKey(privateKey)
            }
        }
    }

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<PrivateKey<Password>>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        _ = inputs[self]
        return .init(Leaf(SecureConnectionNode(
            Node(source: property.source)
        )))
    }
}
