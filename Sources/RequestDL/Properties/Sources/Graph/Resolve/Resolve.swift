//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

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
        try await buildBoundedByResourceDeadline().resolved
    }

    /// ``build()``, also handing back the deadline ``Timeout/Source/resource`` establishes for
    /// this request — taken partway *through* resolution rather than after it.
    ///
    /// `sessionConfiguration(for:)` below can resolve a system proxy, which on Darwin means
    /// fetching and running a PAC script over the network. That is unbounded, remote work, and
    /// exactly the kind of thing a resource budget is supposed to cover; a deadline created only
    /// once `build()` has returned starts counting after it, so a hung PAC lookup outlasts any
    /// `.resource` the caller configured.
    ///
    /// Resolution can't be bounded any earlier than this: the budget itself is declared by a
    /// `Timeout` property, so it isn't known until `partiallyBuild()` has walked the graph. That
    /// half is pure, in-process tree building with nothing remote in it, which is what makes the
    /// split safe to draw here.
    func buildBoundedByResourceDeadline() async throws -> (
        resolved: Resolved,
        deadline: Internals.ResourceDeadline
    ) {
        var (_, make) = try await partiallyBuild()
        applyingURLOverride(&make)

        let deadline = Internals.ResourceDeadline(
            nanoseconds: make.sessionConfiguration.timeout.resource
        )

        let resolvedMake = make
        let configuration = try await deadline.race {
            await sessionConfiguration(for: resolvedMake)
        }

        let session = Internals.Session(
            provider: resolvedMake.provider ?? .shared,
            configuration: configuration
        )

        let resolved = Resolved(
            session: session,
            requestConfiguration: resolvedMake.requestConfiguration,
            dataCache: resolvedMake.cacheConfiguration.build(
                logger: environment.logger
            )
        )

        return (resolved, deadline)
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
    private func sessionConfiguration(for make: Make) async -> Internals.Session.Configuration {
        guard make.resolvesSystemProxy, make.sessionConfiguration.proxy == nil else {
            // An explicit `Proxy` wins. Declaring both leaves the explicit one in effect.
            return make.sessionConfiguration
        }

        var configuration = make.sessionConfiguration

        configuration.proxy = await Internals.SystemProxyResolver.proxy(
            forURL: make.requestConfiguration.url
        )

        return configuration
    }

    /// Rewrites `baseURL`/`pathComponents` per the last-declared `URLOverride` rule whose origin
    /// (scheme + host + optional path prefix) matches the final resolved request.
    ///
    /// Done here rather than inside `URLOverride`'s node for the same reason system-proxy
    /// resolution is: matching needs the final `baseURL`/`pathComponents`, complete only once
    /// every property (including whichever `BaseURL` wins) has contributed. Runs before
    /// `sessionConfiguration(for:)` so a resolved system proxy answers for the overridden
    /// destination, not the original one.
    private func applyingURLOverride(_ make: inout Make) {
        guard
            !make.urlOverrides.isEmpty,
            let origin = URLOverrideEndpoint(baseURL: make.requestConfiguration.baseURL)
        else {
            return
        }

        let pathComponents = Array(
            make.requestConfiguration.pathComponents
                .joinedAsPath()
                .split(separator: "/")
                .map(String.init)
        )

        var match: (destination: URLOverrideEndpoint, remainder: [String])?

        for rule in make.urlOverrides {
            guard
                rule.origin.scheme == origin.scheme,
                rule.origin.host == origin.host,
                pathComponents.starts(with: rule.origin.pathComponents)
            else {
                continue
            }

            match = (rule.destination, Array(pathComponents.dropFirst(rule.origin.pathComponents.count)))
        }

        guard let (destination, remainder) = match else {
            return
        }

        make.requestConfiguration.baseURL = "\(destination.scheme)://\(destination.host)"
        make.requestConfiguration.pathComponents = destination.pathComponents + remainder
    }

    private func inputs() -> _PropertyInputs {
        .init(
            environment: environment,
            namespaceID: .global,
            seedFactory: .init()
        )
    }

    private func outputs() async throws -> _PropertyOutputs {
        try await PropertyResolutionLogger.$current.withValue(environment.logger) {
            try await _Root._makeProperty(
                property: root,
                inputs: inputs()
            )
        }
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
