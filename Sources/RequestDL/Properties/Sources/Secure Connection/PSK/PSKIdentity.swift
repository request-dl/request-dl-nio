/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOSSL

/// A struct representing a pre-shared key (PSK).
public struct PSKIdentity: Property {

    private enum Source {
        case client(SSLPSKClientIdentityResolver)
        case server(SSLPSKServerIdentityResolver)
    }

    private let source: Source
    private var hint: String?

    /// Creates a PSK identity for client-side authentication with the given resolver.
    ///
    /// - Parameters:
    ///   - resolver: The client PSK identity resolver.
    public init(_ resolver: SSLPSKClientIdentityResolver) {
        self.source = .client(resolver)
    }

    /// Creates a PSK identity for server-side authentication with the given resolver.
    ///
    /// - Parameters:
    ///   - resolver: The server PSK identity resolver.
    public init(_ resolver: SSLPSKServerIdentityResolver) {
        self.source = .server(resolver)
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
            case .client(let resolver):
                secureConnection.pskClientIdentityResolver = resolver
            case .server(let resolver):
                secureConnection.pskServerIdentityResolver = resolver
            }
        }
    }

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<PSKIdentity>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()
        return .init(Leaf(SecureConnectionNode(
            Node(
                source: property.source,
                hint: property.hint
            )
        )))
    }
}

extension PSKIdentity {

    /// Creates a PSK identity for client-side authentication with the given type and closure that
    /// generates the PSK.
    ///
    /// - Parameters:
    ///   - psk: The PSK type.
    ///   - closure: A closure that generates a PSK client for a given client description.
    @available(*, deprecated, renamed: "init(_:)")
    public init(
        _ psk: PSKClient,
        _ closure: @Sendable @escaping (PSKClientDescription) throws -> PSKClientIdentity
    ) {
        self.init(ClientResolver(closure))
    }

    /// Creates a PSK identity for server-side authentication with the given type and closure that
    /// generates the PSK.
    ///
    /// - Parameters:
    ///   - psk: The PSK type.
    ///   - closure: A closure that generates a PSK server for a given server description.
    @available(*, deprecated, renamed: "init(_:)")
    public init(
        _ psk: PSKServer,
        _ closure: @Sendable @escaping (PSKServerDescription) throws -> PSKServerIdentity
    ) {
        self.init(ServerResolver(closure))
    }

    /// Creates a PSK identity for client-side authentication with the given type and closure that
    /// generates the PSK.
    ///
    /// - Parameter closure: A closure that generates a PSK client for a given client description.
    @available(*, deprecated, renamed: "init(_:)")
    public init(
        _ closure: @Sendable @escaping (PSKClientDescription) throws -> PSKClientIdentity
    ) {
        self.init(.client, closure)
    }
}

@available(*, deprecated)
extension PSKIdentity {

    fileprivate final class ClientResolver: SSLPSKClientIdentityResolver {

        private let resolver: @Sendable (PSKClientDescription) throws -> PSKClientIdentity

        init(_ resolver: @Sendable @escaping (PSKClientDescription) throws -> PSKClientIdentity) {
            self.resolver = resolver
        }

        func callAsFunction(_ hint: String) throws -> PSKClientIdentityResponse {
            let response = try resolver(.init(hint))
            return .init(
                key: response.key,
                identity: response.identity
            )
        }
    }

    fileprivate final class ServerResolver: SSLPSKServerIdentityResolver {

        private let resolver: @Sendable (PSKServerDescription) throws -> PSKServerIdentity

        init(_ resolver: @Sendable @escaping (PSKServerDescription) throws -> PSKServerIdentity) {
            self.resolver = resolver
        }

        func callAsFunction(_ hint: String, client identity: String) throws -> PSKServerIdentityResponse {
            let response = try resolver(.init(serverHint: hint, clientHint: identity))
            return .init(key: response.key)
        }
    }
}
