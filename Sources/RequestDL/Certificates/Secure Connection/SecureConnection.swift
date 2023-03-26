/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import RequestDLInternals

public struct SecureConnection<Content: Property>: Property {

    private let content: Content

    private var secureConnection: RequestDLInternals.Session.SecureConnection

    public init(
        _ context: SecureConnectionContext = .client,
        @PropertyBuilder content: () -> Content
    ) {
        self.secureConnection = .init(context.build())
        self.content = content()
    }

    public var body: Never {
        bodyException()
    }

    func edit(_ edit: (inout Self) -> Void) -> Self {
        var mutableSelf = self
        edit(&mutableSelf)
        return mutableSelf
    }

    public static func makeProperty(
        _ property: SecureConnection<Content>,
        _ context: Context
    ) async throws {
        let node = Node(
            root: context.root,
            object: EmptyObject(property),
            children: []
        )

        let newContext = Context(node)
        try await Content.makeProperty(property.content, newContext)

        let parameters = newContext
            .findCollection(SecureConnectionNode.self)

        context.append(Node(
            root: context.root,
            object: Object(
                secureConnection: property.secureConnection,
                items: parameters
            ),
            children: []
        ))
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
            maximum: range.upperBound
        )
    }
}

extension SecureConnection {

    public func keyLog(_ closure: @escaping (DataBuffer) -> Void) -> Self {
        edit {
            $0.secureConnection.keyLogCallback = {
                var buffer = $0
                var dataBuffer = DataBuffer()

                if let data = buffer.readData(length: buffer.readableBytes) {
                    dataBuffer.writeData(data)
                }

                closure(dataBuffer)
            }
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
        edit { $0.secureConnection.sendCANameList = isDisabled }
    }
}

extension SecureConnection {

    public func cipherSuites(_ suites: String...) -> Self {
        suites.forEach { precondition(!$0.contains(":")) }
        return edit { $0.secureConnection.cipherSuites = suites.joined(separator: ":") }
    }
}

extension SecureConnection {

    class Object: NodeObject {

        private var secureConnection: RequestDLInternals.Session.SecureConnection
        private let items: [SecureConnectionNode]

        init(
            secureConnection: RequestDLInternals.Session.SecureConnection,
            items: [SecureConnectionNode]
        ) {
            self.secureConnection = secureConnection
            self.items = items
        }

        func makeProperty(_ make: Make) async throws {
            for item in items {
                try await item(&secureConnection)
            }

            make.configuration.secureConnection = secureConnection
        }
    }
}
