/*
 See LICENSE for this package's licensing information.
*/

import Foundation

protocol SecureConnectionCollectorPropertyNode: Sendable {

    func make(_ collector: inout SecureConnectionNode.Collector)
}

protocol SecureConnectionPropertyNode: Sendable {

    func make(_ secureConnection: inout Internals.SecureConnection)
}

struct SecureConnectionNode: PropertyNode {

    // MARK: - Private properties

    private let source: Source

    // MARK: - Inits

    init(_ node: SecureConnectionCollectorPropertyNode) {
        self.source = .collectorNode(node)
    }

    init(_ node: SecureConnectionPropertyNode) {
        self.source = .node(node)
    }

    // MARK: - Internal methods

    func make(_ make: inout Make) async throws {
        guard let secureConnection = make.configuration.secureConnection else {
            Internals.Log.failure(
                .cantCreateCertificateOutsideSecureConnection()
            )
        }

        var collector = secureConnection.collector()
        passthrough(&collector)
        make.configuration.secureConnection = collector(\.self)
    }
}

extension SecureConnectionNode {

    fileprivate enum Source: Sendable {
        case collectorNode(SecureConnectionCollectorPropertyNode)
        case node(SecureConnectionPropertyNode)
    }
}

// MARK: - Contains

extension SecureConnectionNode {

    struct Contains: Sendable {

        // MARK: - Private properties

        fileprivate let source: Source

        // MARK: - Internal methods

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

// MARK: - Passthrough

extension SecureConnectionNode {

    struct Passthrough: Sendable {

        // MARK: - Private properties

        fileprivate let source: Source

        // MARK: - Internal methods

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

// MARK: - Collector

extension SecureConnectionNode {

    struct Collector: Sendable {

        // MARK: - Internal properties

        var certificateChain: [Internals.Certificate]?

        var trustRoots: [Internals.Certificate]?

        var additionalTrustRoots: [Internals.Certificate]?

        // MARK: - Private properties

        fileprivate var secureConnection: Internals.SecureConnection

        // MARK: - Inits

        fileprivate init(_ secureConnection: Internals.SecureConnection) {
            self.secureConnection = secureConnection
        }

        // MARK: - Internal methods

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

        // MARK: - Private methods

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
    }
}

// MARK: - Internals.SecureConnection extension

extension Internals.SecureConnection {

    func collector() -> SecureConnectionNode.Collector {
        .init(self)
    }
}
