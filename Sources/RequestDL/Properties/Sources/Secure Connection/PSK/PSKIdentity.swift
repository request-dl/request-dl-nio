/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/// A struct representing a pre-shared key (PSK).
public struct PSKIdentity<PSK: PSKType>: Property {

    private enum Source {
        case server((PSKServerDescription) throws -> PSKServerIdentity)
        case client((PSKClientDescription) throws -> PSKClientIdentity)
    }

    private let source: Source
    private var hint: String?

    /// Creates a PSK identity for client-side authentication with the given type and closure that
    /// generates the PSK.
    ///
    /// - Parameters:
    ///   - psk: The PSK type.
    ///   - closure: A closure that generates a PSK client for a given client description.
    public init(
        _ psk: PSK,
        _ closure: @escaping (PSKClientDescription) throws -> PSKClientIdentity
    ) where PSK == PSKClient {
        source = .client(closure)
    }

    /// Creates a PSK identity for server-side authentication with the given type and closure that
    /// generates the PSK.
    ///
    /// - Parameters:
    ///   - psk: The PSK type.
    ///   - closure: A closure that generates a PSK server for a given server description.
    public init(
        _ psk: PSK,
        _ closure: @escaping (PSKServerDescription) throws -> PSKServerIdentity
    ) where PSK == PSKServer {
        source = .server(closure)
    }

    /// Creates a PSK identity for client-side authentication with the given type and closure that
    /// generates the PSK.
    ///
    /// - Parameter closure: A closure that generates a PSK client for a given client description.
    public init(
        _ closure: @escaping (PSKClientDescription) throws -> PSKClientIdentity
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

extension PSKIdentity {

    /// Adds a hint to the PSK.
    ///
    /// - Parameter hint: A hint string to be associated with the identity.
    /// - Returns: The PSK instance with the hint added.
    public func hint(_ hint: String) -> Self {
        edit { $0.hint = hint }
    }
}

extension PSKIdentity {

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
        property: _GraphValue<PSKIdentity<PSK>>,
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
