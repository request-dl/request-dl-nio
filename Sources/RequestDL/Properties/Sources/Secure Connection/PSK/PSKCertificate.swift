/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/// A struct representing a pre-shared key (PSK) certificate.
public struct PSKCertificate<PSK: PSKType>: Property {

    private enum Source {
        case server((PSKServerDescription) throws -> PSKServerCertificate)
        case client((PSKClientDescription) throws -> PSKClientCertificate)
    }

    private let source: Source
    private var hint: String?

    /// Creates a PSK certificate for client-side authentication with the given PSK and closure that
    /// generates a PSK client certificate.
    ///
    /// - Parameters:
    ///   - psk: The pre-shared key (PSK) for the certificate.
    ///   - closure: A closure that generates a PSK client certificate given a PSK client description.
    public init(
        _ psk: PSK,
        _ closure: @escaping (PSKClientDescription) throws -> PSKClientCertificate
    ) where PSK == PSKClient {
        source = .client(closure)
    }

    /// Creates a PSK certificate for server-side authentication with the given PSK and closure that
    /// generates a PSK server certificate.
    ///
    /// - Parameters:
    ///   - psk: The pre-shared key (PSK) for the certificate.
    ///   - closure: A closure that generates a PSK server certificate given a PSK server description.
    public init(
        _ psk: PSK,
        _ closure: @escaping (PSKServerDescription) throws -> PSKServerCertificate
    ) where PSK == PSKServer {
        source = .server(closure)
    }

    /// Creates a PSK certificate for client-side authentication with the given closure that generates a PSK
    /// client certificate.
    ///
    /// - Parameters:
    ///   - closure: A closure that generates a PSK client certificate given a PSK client description.
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

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }
}

extension PSKCertificate {

    /// Adds a hint to the PSK certificate.
    ///
    /// - Parameter hint: A hint string to be associated with the PSK certificate.
    /// - Returns: The PSK certificate instance with the hint added.
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

    /// This method is used internally and should not be called directly.
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
