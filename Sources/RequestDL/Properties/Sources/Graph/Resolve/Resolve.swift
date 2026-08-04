//
// See LICENSE for this package's licensing information.
//

struct Resolve<Root: Property>: Sendable {

    // MARK: - Private properties

    private let root: _GraphValue<_Root>
    private let environment: RequestEnvironmentValues

    // MARK: - Inits

    init(
        root: Root,
        environment: RequestEnvironmentValues
    ) {
        self.root = .root(.init(body: root))
        self.environment = environment
    }

    // MARK: - Internal methods

    func build() async throws -> Resolved {
        let (_, make) = try await partiallyBuild()

        let session = Internals.Session(
            provider: make.provider ?? .shared,
            configuration: sessionConfiguration(for: make)
        )

        return Resolved(
            session: session,
            requestConfiguration: make.requestConfiguration,
            dataCache: make.cacheConfiguration.build(
                logger: environment.logger
            )
        )
    }

    func partiallyBuild() async throws -> (_PropertyOutputs, Make) {
        let output = try await outputs()

        var make = Make(
            sessionConfiguration: .init(),
            requestConfiguration: .init()
        )

        try await output.node._make(&make)
        return (output, make)
    }

    func description() async throws -> String {
        let title = "Resolve"
        let outputs = try await outputs()

        let nodesDescription = outputs.node
            .nodeDescription
            .debug_shiftLines()

        return """
            \(title) {
            \(nodesDescription)
            }
            """
    }

    // MARK: - Private methods

    /// Folds a resolved system proxy into the session configuration.
    ///
    /// Done here rather than inside `SystemProxy`'s node because the system's answer depends on
    /// the URL, and the URL is only complete once every property has contributed to it. A node
    /// declared before `BaseURL` would otherwise resolve against an empty address.
    ///
    /// The resolved proxy lands in the configuration, so the client cache partitions by it the
    /// same way it does for an explicit one.
    private func sessionConfiguration(for make: Make) -> Internals.Session.Configuration {
        guard make.resolvesSystemProxy, make.sessionConfiguration.proxy == nil else {
            // An explicit `Proxy` wins. Declaring both leaves the explicit one in effect.
            return make.sessionConfiguration
        }

        var configuration = make.sessionConfiguration

        configuration.proxy = Internals.SystemProxyResolver.proxy(
            forURL: make.requestConfiguration.url
        )

        return configuration
    }

    private func inputs() -> _PropertyInputs {
        .init(
            environment: environment,
            namespaceID: .global,
            seedFactory: .init()
        )
    }

    private func outputs() async throws -> _PropertyOutputs {
        try await _Root._makeProperty(
            property: root,
            inputs: inputs()
        )
    }
}

extension Resolve {

    struct _Root: Property {
        let body: Root
    }
}

// MARK: - Node extension

extension Node {

    fileprivate func _make(_ make: inout Make) async throws {
        if let property = self as? PropertyNode {
            try await property.make(&make)
        }

        for child in children {
            try await child._make(&make)
        }
    }
}
