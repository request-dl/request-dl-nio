/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public struct PSKCertificate<PSK: PSKType>: Property {

    private enum Source {
        case server((PSKServerDescription) throws -> PSKServerCertificate)
        case client((PSKClientDescription) throws -> PSKClientCertificate)
    }

    private let source: Source
    private var hint: String?

    public init(
        _ psk: PSK,
        _ closure: @escaping (PSKClientDescription) throws -> PSKClientCertificate
    ) where PSK == PSKClient {
        source = .client(closure)
    }

    public init(
        _ psk: PSK,
        _ closure: @escaping (PSKServerDescription) throws -> PSKServerCertificate
    ) where PSK == PSKServer {
        source = .server(closure)
    }

    public init(
        _ closure: @escaping (PSKClientDescription) throws -> PSKClientCertificate
    ) where PSK == PSKClient {
        self.init(.client, closure)
    }

    fileprivate func edit(_ edit: (inout Self) -> Void) -> Self {
        var mutableSelf = self
        edit(&mutableSelf)
        return mutableSelf
    }

    public var body: Never {
        bodyException()
    }
}

extension PSKCertificate {

    public func hint(_ hint: String) -> Self {
        edit { $0.hint = hint }
    }
}

extension PSKCertificate {

    private struct Node: SecureConnectionPropertyNode {

        let source: Source
        let hint: String?

        func make(_ secureConnection: inout Internals.SecureConnection) {
            secureConnection.pskHint = hint

            switch source {
            case .client(let closure):
                secureConnection.pskClientCallback = {
                    try closure(.init($0)).build()
                }
            case .server(let closure):
                secureConnection.pskServerCallback = {
                    try closure(.init(
                        serverHint: $0,
                        clientHint: $1
                    )).build()
                }
            }
        }
    }

    public static func _makeProperty(
        property: _GraphValue<PSKCertificate<PSK>>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        _ = inputs[self]
        return .init(Leaf(SecureConnectionNode(
            Node(
                source: property.source,
                hint: property.hint
            )
        )))
    }
}
