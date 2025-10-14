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

    struct Collector: Sendable {

        // MARK: - Internal properties

        #if !canImport(Network)
        var certificateChain: [Internals.Certificate]?
        #endif

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
            #if !canImport(Network)
            case \.certificateChain:
                setCertificateChain(&secureConnection)
            #endif
            case \.trustRoots:
                setTrustRoots(&secureConnection)
            case \.additionalTrustRoots:
                setAdditionalTrustRoots(&secureConnection)
            default:
                #if !canImport(Network)
                setCertificateChain(&secureConnection)
                #endif
                setTrustRoots(&secureConnection)
                setAdditionalTrustRoots(&secureConnection)
            }

            return secureConnection
        }

        // MARK: - Private methods

        #if !canImport(Network)
        private func setCertificateChain(_ secureConnection: inout Internals.SecureConnection) {
            if let certificateChain {
                secureConnection.certificateChain = .certificates(certificateChain)
            }
        }
        #endif

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

    fileprivate enum Source: Sendable {
        case collectorNode(SecureConnectionCollectorPropertyNode)
        case node(SecureConnectionPropertyNode)
    }

    // MARK: - Internal properties

    var contains: Contains {
        .init(source: source)
    }

    var passthrough: Passthrough {
        .init(source: source)
    }

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
            Internals.Log.warning(
                .cantCreateCertificateOutsideSecureConnection()
            )
            return
        }

        var collector = secureConnection.collector()
        passthrough(&collector)
        make.configuration.secureConnection = collector(\.self)
    }
}

// MARK: - Internals.SecureConnection extension

extension Internals.SecureConnection {

    func collector() -> SecureConnectionNode.Collector {
        .init(self)
    }
}
