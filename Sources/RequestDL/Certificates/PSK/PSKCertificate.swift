/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import RequestDLInternals

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

extension PSKCertificate: PrimitiveProperty {

    func makeObject() -> SecureConnectionNode {
        SecureConnectionNode {
            $0.pskHint = hint

            switch source {
            case .client(let closure):
                $0.pskClientCallback = {
                    try closure(.init($0)).build()
                }
            case .server(let closure):
                $0.pskServerCallback = {
                    try closure(.init(
                        serverHint: $0,
                        clientHint: $1
                    )).build()
                }
            }
        }
    }
}
