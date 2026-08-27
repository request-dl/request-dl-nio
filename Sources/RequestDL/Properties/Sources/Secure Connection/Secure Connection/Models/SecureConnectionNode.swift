//
// See LICENSE for this package's licensing information.
//

import Logging
import RequestDLInternals

protocol SecureConnectionCollectorPropertyNode: Sendable {

    func make(_ collector: inout SecureConnectionNode.Collector)
}

protocol SecureConnectionPropertyNode: Sendable {

    func make(_ secureConnection: inout Internals.SecureConnection)
}

struct SecureConnectionNode: PropertyNode {

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

    struct Contains: Sendable {

        // MARK: - Private properties

        fileprivate let source: Source

        // MARK: - Internal methods

        func callAsFunction<Property>(_ type: Property.Type) -> Bool {
            switch source {
            case .collectorNode(let property):
                return property is Property
            case .node(let property), .root(let property):
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
            case .node(let node), .root(let node):
                node.make(&collector.secureConnection)
            case .collectorNode(let node):
                node.make(&collector)
            }
        }
    }

    fileprivate enum Source: Sendable {
        case collectorNode(SecureConnectionCollectorPropertyNode)
        case node(SecureConnectionPropertyNode)
        // Only ever constructed by `SecureConnection` itself. Unlike `.node` — which requires an
        // already-established `Internals.SecureConnection` to attach to, and warns when used
        // without one — `.root` is allowed to be the thing that establishes it: at the true top
        // of the graph, `make.sessionConfiguration.secureConnection` starts out nil, and that's
        // the expected starting state for `SecureConnection`, not a misuse warning worth logging.
        case root(SecureConnectionPropertyNode)
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
    private let logger: Logger?

    // MARK: - Inits

    init(_ node: SecureConnectionCollectorPropertyNode, logger: Logger?) {
        self.source = .collectorNode(node)
        self.logger = logger
    }

    init(_ node: SecureConnectionPropertyNode, logger: Logger?) {
        self.source = .node(node)
        self.logger = logger
    }

    init(root node: SecureConnectionPropertyNode, logger: Logger?) {
        self.source = .root(node)
        self.logger = logger
    }

    // MARK: - Internal methods

    func make(_ make: inout Make) async throws {
        let secureConnection: Internals.SecureConnection

        if let existing = make.sessionConfiguration.secureConnection {
            secureConnection = existing
        } else if case .root = source {
            secureConnection = .init()
        } else {
            #if DEBUG
            Internals.Log.cantCreateCertificateOutsideSecureConnection().log(
                level: .warning,
                logger: logger
            )
            #endif
            return
        }

        var collector = secureConnection.collector()
        passthrough(&collector)
        make.sessionConfiguration.secureConnection = collector(\.self)
    }
}

// MARK: - Internals.SecureConnection extension

extension Internals.SecureConnection {

    func collector() -> SecureConnectionNode.Collector {
        .init(self)
    }
}
