/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 A property for secure connections.

 Use SecureConnection to create a secure connection for your request. You can set the minimum and
 maximum TLS versions that your app supports.
 */
public struct SecureConnection<Content: Property>: Property {

    private let content: Content

    private var configuration: (URLSessionConfiguration) -> Void

    /**
     Initializes a new instance of `SecureConnection` with the given content.

     - Parameter content: A closure that returns the `Content` of secure connection properties.
     */
    public init(
        @PropertyBuilder content: () -> Content
    ) {
        self.configuration = { _ in }
        self.content = content()
    }

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    func edit(_ edit: @escaping (URLSessionConfiguration) -> Void) -> Self {
        var mutableSelf = self
        let old = configuration
        mutableSelf.configuration = {
            edit($0)
            old($0)
        }
        return mutableSelf
    }
}

extension SecureConnection {

    /**
     Sets the minimum TLS version that the connection should support.

     - Parameter minimum: The minimum TLS version to support.

     - Returns: A new instance of `SecureConnection` with the specified minimum TLS version.
     */
    public func version(minimum: TLSVersion) -> Self {
        edit { $0.tlsMinimumSupportedProtocolVersion = minimum.build() }
    }

    /**
     Sets the maximum TLS version that the connection should support.

     - Parameter maximum: The maximum TLS version to support.

     - Returns: A new instance of `SecureConnection` with the specified maximum TLS version.
     */
    public func version(maximum: TLSVersion) -> Self {
        edit { $0.tlsMaximumSupportedProtocolVersion = maximum.build() }
    }

    /**
     Sets the minimum and maximum TLS versions that the connection should support.

     - Parameters:
        - minimum: The minimum TLS version to support.
        - maximum: The maximum TLS version to support.

     - Returns: A new instance of `SecureConnection` with the specified minimum and maximum TLS versions.
     */
    public func version(minimum: TLSVersion, maximum: TLSVersion) -> Self {
        version(minimum: minimum).version(maximum: maximum)
    }
}

extension SecureConnection {

    private struct Node: PropertyNode {

        let configuration: (URLSessionConfiguration) -> Void
        let nodes: [Leaf<SecureConnectionNode>]

        func make(_ make: inout Make) async throws {
            configuration(make.configuration)

            make.isInsideSecureConnection = true
            for node in nodes {
                try await node.make(&make)
            }
            make.isInsideSecureConnection = false
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
            configuration: property.configuration,
            nodes: outputs.node.search(for: SecureConnectionNode.self)
        )))
    }
}
