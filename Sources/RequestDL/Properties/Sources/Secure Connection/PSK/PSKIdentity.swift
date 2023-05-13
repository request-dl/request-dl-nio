/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOSSL

/// A struct representing a pre-shared key (PSK).
public struct PSKIdentity: Property {

    private struct Node: SecureConnectionPropertyNode {

        let source: Source
        let hint: String?

        func make(_ secureConnection: inout Internals.SecureConnection) {
            secureConnection.pskHint = hint

            switch source {
            case .resolver(let resolver):
                secureConnection.pskIdentityResolver = resolver
            case .deprecated:
                Internals.Log.warning(
                    .deprecatedServerConfiguration()
                )
            }
        }
    }

    private enum Source: Sendable {
        case resolver(SSLPSKIdentityResolver)
        case deprecated
    }

    // MARK: - Public properties

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    // MARK: - Private properties

    private let source: Source
    private var hint: String?

    // MARK: - Inits

    /// Creates a PSK identity for client-side authentication with the given resolver.
    ///
    /// - Parameters:
    ///   - resolver: The client PSK identity resolver.
    public init(_ resolver: SSLPSKIdentityResolver) {
        self.source = .resolver(resolver)
    }

    // MARK: - Public static methods

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<PSKIdentity>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()
        return .leaf(SecureConnectionNode(
            Node(
                source: property.source,
                hint: property.hint
            )
        ))
    }

    // MARK: - Public methods

    /// Adds a hint to the PSK.
    ///
    /// - Parameter hint: A hint string to be associated with the identity.
    /// - Returns: The PSK instance with the hint added.
    public func hint(_ hint: String) -> Self {
        edit { $0.hint = hint }
    }

    // MARK: - Private methods

    private func edit(_ edit: (inout Self) -> Void) -> Self {
        var mutableSelf = self
        edit(&mutableSelf)
        return mutableSelf
    }
}

// MARK: - Deprecated

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
        _ closure: @escaping @Sendable (PSKClientDescription) throws -> PSKClientIdentity
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
        _ closure: @escaping @Sendable (PSKServerDescription) throws -> PSKServerIdentity
    ) {
        self.source = .deprecated
    }

    /// Creates a PSK identity for client-side authentication with the given type and closure that
    /// generates the PSK.
    ///
    /// - Parameter closure: A closure that generates a PSK client for a given client description.
    @available(*, deprecated, renamed: "init(_:)")
    public init(
        _ closure: @escaping @Sendable (PSKClientDescription) throws -> PSKClientIdentity
    ) {
        self.init(.client, closure)
    }
}

@available(*, deprecated)
extension PSKIdentity {

    fileprivate final class ClientResolver: SSLPSKIdentityResolver {

        private let resolver: @Sendable (PSKClientDescription) throws -> PSKClientIdentity

        init(_ resolver: @escaping @Sendable (PSKClientDescription) throws -> PSKClientIdentity) {
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
}
