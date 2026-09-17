//
// See LICENSE for this package's licensing information.
//

// Only ever meaningful under `.nio`: a PSK identity resolver is a TLS handshake hook with no
// Network.framework/URLSession equivalent, same reasoning as `SSLKeyLogger`'s own gate. This
// whole type only exists to set `Internals.SecureConnection.pskHint`/`.pskIdentityResolver`,
// which are themselves gated the same way.
#if canImport(NIOCore)

import NIOSSL
import RequestDLInternals

/// A struct representing a pre-shared key (PSK).
public struct PSKIdentity: Property {

    private struct Node: SecureConnectionPropertyNode {

        let resolver: SSLPSKIdentityResolver
        let hint: String?

        func make(_ secureConnection: inout Internals.SecureConnection) throws {
            secureConnection.pskHint = hint
            secureConnection.pskIdentityResolver = resolver
        }
    }

    // MARK: - Public properties

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    // MARK: - Private properties

    private let resolver: SSLPSKIdentityResolver
    private var hint: String?

    // MARK: - Inits

    /// Creates a PSK identity for client-side authentication with the given resolver.
    ///
    /// - Parameters:
    ///   - resolver: The client PSK identity resolver.
    public init(_ resolver: SSLPSKIdentityResolver) {
        self.resolver = resolver
    }

    // MARK: - Public static methods

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<PSKIdentity>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()
        return .leaf(
            SecureConnectionNode(
                Node(
                    resolver: property.resolver,
                    hint: property.hint
                ),
                logger: inputs.environment.logger
            )
        )
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

#endif
