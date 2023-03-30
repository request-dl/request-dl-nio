/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import RequestDLInternals

public struct SecureConnection<Content: Property>: Property {

    private let content: Content

    private var secureConnection: Internals.SecureConnection

    public init(
        _ context: SecureConnectionContext = .client,
        @PropertyBuilder content: () -> Content
    ) {
        self.secureConnection = .init(context.build())
        self.content = content()
    }

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    func edit(_ edit: (inout Self) -> Void) -> Self {
        var mutableSelf = self
        edit(&mutableSelf)
        return mutableSelf
    }
}

extension SecureConnection {

    public func version(minimum: TLSVersion) -> Self {
        edit { $0.secureConnection.minimumTLSVersion = minimum.build() }
    }

    public func version(maximum: TLSVersion) -> Self {
        edit { $0.secureConnection.maximumTLSVersion = maximum.build() }
    }

    public func version(minimum: TLSVersion, maximum: TLSVersion) -> Self {
        version(minimum: minimum).version(maximum: maximum)
    }

    public func version(_ range: Range<TLSVersion>) -> Self {
        version(
            minimum: range.lowerBound,
            maximum: range.upperBound.downgrade
        )
    }

    public func version(_ range: ClosedRange<TLSVersion>) -> Self {
        version(
            minimum: range.lowerBound,
            maximum: range.upperBound
        )
    }
}

extension SecureConnection {

    public func keyLog(
        _ closure: @Sendable @escaping (ByteBuffer) -> Void
    ) -> Self {
        edit {
            $0.secureConnection.keyLogCallback = closure
        }
    }
}

extension SecureConnection {

    public func shutdownTimeout(_ timeout: UnitTime) -> Self {
        edit { $0.secureConnection.shutdownTimeout = timeout.build() }
    }
}

extension SecureConnection {

    public func renegotiationSupport(_ renegotiationSupport: NIORenegotiationSupport) -> Self {
        edit { $0.secureConnection.renegotiationSupport = renegotiationSupport }
    }
}

extension SecureConnection {

    public func signingSignatureAlgorithms(_ algorithm: SignatureAlgorithm...) -> Self {
        edit { $0.secureConnection.signingSignatureAlgorithms = algorithm }
    }

    public func verifySignatureAlgorithms(_ algorithm: SignatureAlgorithm...) -> Self {
        edit { $0.secureConnection.verifySignatureAlgorithms = algorithm }
    }
}

extension SecureConnection {

    public func verification(_ verification: CertificateVerification) -> Self {
        edit { $0.secureConnection.certificateVerification = verification }
    }
}

extension SecureConnection {

    public func applicationProtocols(_ protocols: String...) -> Self {
        edit { $0.secureConnection.applicationProtocols = protocols }
    }
}

extension SecureConnection {

    public func sendCANameListDisabled(_ isDisabled: Bool) -> Self {
        edit { $0.secureConnection.sendCANameList = !isDisabled }
    }
}

extension SecureConnection {

    public func cipherSuites(_ suites: String...) -> Self {
        suites.forEach { precondition(!$0.contains(":")) }
        return edit { $0.secureConnection.cipherSuites = suites.joined(separator: ":") }
    }

    public func cipherSuites(_ suites: NIOTLSCipher...) -> Self {
        return edit { $0.secureConnection.cipherSuiteValues = suites }
    }
}

extension SecureConnection {

    private struct Node: PropertyNode {

        let secureConnection: Internals.SecureConnection
        let nodes: [Leaf<SecureConnectionNode>]

        func make(_ make: inout Make) async throws {
            make.configuration.secureConnection = secureConnection

            for node in nodes {
                try await node.make(&make)
            }
        }
    }

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<SecureConnection<Content>>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        let inputs = inputs[self, \.content]

        let outputs = try await Content._makeProperty(
            property: property.content,
            inputs: inputs
        )

        return .init(Leaf(Node(
            secureConnection: property.secureConnection,
            nodes: outputs.node.search(for: SecureConnectionNode.self)
        )))
    }
}
