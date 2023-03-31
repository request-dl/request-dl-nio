/*
 See LICENSE for this package's licensing information.
*/

import Foundation

protocol SecureConnectionCollectorPropertyNode {

    func make(_ collector: inout SecureConnectionNode.Collector)
}

protocol SecureConnectionPropertyNode {

    func make(_ secureConnection: inout Internals.SecureConnection)
}

struct SecureConnectionNode: PropertyNode {

    private let source: Source

    init(_ node: SecureConnectionCollectorPropertyNode) {
        self.source = .collectorNode(node)
    }

    init(_ node: SecureConnectionPropertyNode) {
        self.source = .node(node)
    }

    func make(_ make: inout Make) async throws {
        guard let secureConnection = make.configuration.secureConnection else {
            Internals.Log.failure(
                """
                An attempt was made to access the secure connection, but \
                the required property could not be found.

                Please verify that the property is correctly set up inside \
                the SecureConnection property.
                """
            )
        }

        var collector = secureConnection.collector()
        passthrough(&collector)
        make.configuration.secureConnection = collector(\.self)
    }
}

extension SecureConnectionNode {

    fileprivate enum Source {
        case collectorNode(SecureConnectionCollectorPropertyNode)
        case node(SecureConnectionPropertyNode)
    }
}

extension SecureConnectionNode {

    struct Contains {

        fileprivate let source: Source

        func callAsFunction<Property>(_ type: Property.Type) -> Bool {
            switch source {
            case .collectorNode(let property):
                return property is Property
            case .node(let property):
                return property is Property
            }
        }
    }

    var contains: Contains {
        .init(source: source)
    }
}

extension SecureConnectionNode {

    struct Passthrough {

        fileprivate let source: Source

        func callAsFunction(_ collector: inout Collector) {
            switch source {
            case .node(let node):
                node.make(&collector.secureConnection)
            case .collectorNode(let node):
                node.make(&collector)
            }
        }
    }

    var passthrough: Passthrough {
        .init(source: source)
    }
}

extension SecureConnectionNode {

    struct Collector {

        var certificateChain: [Internals.Certificate]?

        var trustRoots: [Internals.Certificate]?

        var additionalTrustRoots: [Internals.Certificate]?

        fileprivate var secureConnection: Internals.SecureConnection

        fileprivate init(_ secureConnection: Internals.SecureConnection) {
            self.secureConnection = secureConnection
        }
    }
}

extension SecureConnectionNode.Collector {

    private func setCertificateChain(_ secureConnection: inout Internals.SecureConnection) {
        if let certificateChain {
            secureConnection.certificateChain = .certificates(certificateChain)
        }
    }

    private func setTrustRoots(_ secureConnection: inout Internals.SecureConnection) {
        if let trustRoots {
            secureConnection.trustRoots = .certificates(trustRoots)
        }
    }

    private func setAdditionalTrustRoots(_ secureConnection: inout Internals.SecureConnection) {
        if let additionalTrustRoots {
            var sc_additionalTrustRoots = secureConnection.additionalTrustRoots ?? []
            sc_additionalTrustRoots.append(.certificates(additionalTrustRoots))
            secureConnection.additionalTrustRoots = sc_additionalTrustRoots
        }
    }

    func callAsFunction<Value>(_ keyPath: KeyPath<Self, Value>) -> Internals.SecureConnection {
        var secureConnection = secureConnection

        switch keyPath {
        case \.certificateChain:
            setCertificateChain(&secureConnection)
        case \.trustRoots:
            setTrustRoots(&secureConnection)
        case \.additionalTrustRoots:
            setAdditionalTrustRoots(&secureConnection)
        default:
            setCertificateChain(&secureConnection)
            setTrustRoots(&secureConnection)
            setAdditionalTrustRoots(&secureConnection)
        }

        return secureConnection
    }
}

extension Internals.SecureConnection {

    func collector() -> SecureConnectionNode.Collector {
        .init(self)
    }
}
