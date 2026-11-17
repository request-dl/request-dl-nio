//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

struct Resolve<Root: Property>: Sendable {

    // MARK: - Private properties

    private let root: _GraphValue<_Root>
    private let environment: RequestEnvironmentValues
    private let namespaceID: PropertyNamespace.ID
    private let seedFactory: SeedFactory
    private let defaultReadingMode: Internals.DownloadStep.ReadingMode?

    // MARK: - Inits

    /// - Parameters:
    ///   - namespaceID: The `@StoredObject`/`@PropertyNamespace` namespace this resolution runs
    ///   under. Defaults to `.global`, correct for every top-level resolution (`RawTask`,
    ///   `BackgroundDownloadTask`, `PropertyMockedTask`, ...), which have no enclosing namespace
    ///   to inherit.
    ///   - seedFactory: Hands out per-namespace `@StoredObject` identity seeds. Defaults to a
    ///   fresh instance for the same reason `namespaceID` defaults to `.global`: a top-level
    ///   resolution starts counting from zero.
    ///
    ///   - Important: `PropertyReader._makeProperty` is the one caller that must pass its own
    ///   `inputs.namespaceID`/`inputs.seedFactory` explicitly, rather than accepting these
    ///   defaults, when resolving its `source` subtree. `source` is logically still part of the
    ///   ambient tree (its `PropertyContext` result feeds `content`, resolved right after with
    ///   those same `inputs`); minting a fresh `SeedFactory` for it here would let a `source`
    ///   under one `PropertyReader` and a `source` under a sibling `PropertyReader` (or the
    ///   top-level tree) each independently compute seed `.zero` for `.global`, colliding on the
    ///   same `Internals.Storage` entry for any `@StoredObject`-bearing type they happen to share,
    ///   instead of getting independent instances.
    ///   - defaultReadingMode: What the body is chunked by unless a ``ReadingMode`` property says
    ///   otherwise. `nil` keeps `RequestConfiguration`'s own default.
    init(
        root: Root,
        environment: RequestEnvironmentValues,
        namespaceID: PropertyNamespace.ID = .global,
        seedFactory: SeedFactory = SeedFactory(),
        defaultReadingMode: Internals.DownloadStep.ReadingMode? = nil
    ) {
        self.root = .root(.init(body: root))
        self.environment = environment
        self.namespaceID = namespaceID
        self.seedFactory = seedFactory
        self.defaultReadingMode = defaultReadingMode
    }

    // MARK: - Internal methods

    func build() async throws -> Resolved {
        try await buildBoundedByResourceDeadline().resolved
    }

    /// ``build()``, also handing back the deadline ``Timeout/Source/resource`` establishes for
    /// this request, taken partway *through* resolution rather than after it.
    ///
    /// `sessionConfiguration(for:)` below can resolve a system proxy, which on Darwin means
    /// fetching and running a PAC script over the network. That is unbounded, remote work that
    /// a resource budget should cover, and a deadline created only once `build()` has returned
    /// starts counting after it, so a hung PAC lookup would outlast any `.resource` the caller
    /// configured.
    ///
    /// Resolution can't be bounded any earlier: the budget is declared by a `Timeout` property,
    /// so it isn't known until `partiallyBuild()` has walked the graph. That half is pure,
    /// in-process tree building with nothing remote in it, so the split is safe here.
    func buildBoundedByResourceDeadline() async throws -> (
        resolved: Resolved,
        deadline: Internals.ResourceDeadline
    ) {
        var (_, make) = try await partiallyBuild()
        applyingURLOverride(&make)

        // Checked here, on the finished configuration, rather than by whichever property is
        // declared last: `SecureConnection` builds on what was declared before it (or, with
        // `.override`, replaces it), and `.verification` and the pins can come from different
        // declarations, so no single node sees both halves of the combination regardless of
        // declaration order.
        if make.sessionConfiguration.secureConnection?.pinsAreIgnoredWithoutCertificateVerification == true {
            Internals.Log.pinsIgnoredWithoutCertificateVerification().log(
                level: .warning,
                logger: environment.logger
            )
        }

        let deadline = Internals.ResourceDeadline(
            nanoseconds: make.sessionConfiguration.timeout.resource
        )

        let resolvedMake = make
        let configuration = try await deadline.race {
            try await sessionConfiguration(for: resolvedMake)
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

        var requestConfiguration = RequestConfiguration()

        if let defaultReadingMode {
            requestConfiguration.defaultReadingMode = defaultReadingMode
        }

        var make = Make(
            sessionConfiguration: .init(),
            requestConfiguration: requestConfiguration
        )

        try await output.node._make(&make)
        try await resolvingPendingURLEncodedPayloads(&make)
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
    ///
    /// - Throws: ``ProxyAutoConfigurationError`` when the system's proxy is a PAC script that
    /// cannot be asked and the request declared ``SystemProxy/PACFailurePolicy/fail``.
    private func sessionConfiguration(for make: Make) async throws -> Internals.Session.Configuration {
        guard make.resolvesSystemProxy, make.sessionConfiguration.proxy == nil else {
            // An explicit `Proxy` wins. Declaring both leaves the explicit one in effect.
            return make.sessionConfiguration
        }

        var configuration = make.sessionConfiguration

        do {
            configuration.proxy = try await Internals.SystemProxyResolver.proxy(
                forURL: make.requestConfiguration.url,
                pac: make.systemProxyPAC,
                logger: environment.logger
            )
        } catch let failure as Internals.PACEvaluationFailure {
            throw ProxyAutoConfigurationError(failure)
        }

        return configuration
    }

    /// Rewrites `baseURL`/`pathComponents` per the most specific `URLOverride` rule (then the
    /// last declared) whose origin (scheme + host + optional path prefix) matches the final
    /// resolved request, and hands the rules to the session configuration, so the executors apply
    /// them to every redirect hop too (a redirect is followed by the executor and never resolved
    /// again). See ``Internals/URLOverrides``.
    ///
    /// Done here rather than inside `URLOverride`'s node for the same reason system-proxy
    /// resolution is: matching needs the final `baseURL`/`pathComponents`, complete only once
    /// every property (including whichever `BaseURL` wins) has contributed. Runs before
    /// `sessionConfiguration(for:)` so a resolved system proxy answers for the overridden
    /// destination, not the original one.
    private func applyingURLOverride(_ make: inout Make) {
        guard !make.urlOverrides.isEmpty else {
            return
        }

        let overrides = Internals.URLOverrides(rules: make.urlOverrides)

        // Whether or not this request itself is covered: a response may send it to a host that is.
        make.sessionConfiguration.urlOverrides = overrides

        guard let origin = URLOverrideEndpoint(baseURL: make.requestConfiguration.baseURL) else {
            return
        }

        let pathComponents = Array(
            make.requestConfiguration.pathComponents
                .joinedAsPath()
                .split(separator: "/")
                .map(String.init)
        )

        guard let (destination, remainder) = overrides.match(origin: origin, pathComponents: pathComponents)
            .map({ ($0.destination, $0.remainder) })
        else {
            return
        }

        let destinationHost = destination.port.map { "\(destination.host):\($0)" } ?? destination.host
        make.requestConfiguration.baseURL = "\(destination.scheme)://\(destinationHost)"
        make.requestConfiguration.pathComponents = destination.pathComponents + remainder
    }

    /// Resolves every `Payload`-contributed url-encoded field set accumulated during the walk,
    /// in declaration order, now that the tree has finished and `make.requestConfiguration
    /// .method` reflects whichever `RequestMethod` (if any) ultimately won.
    ///
    /// Done here rather than inside `PayloadNode`'s own node, for the same reason
    /// `applyingURLOverride(_:)`/`sessionConfiguration(for:)` are: the decision needs the final
    /// state, complete only once every property has contributed. See
    /// `PendingURLEncodedPayload`'s own doc comment.
    private func resolvingPendingURLEncodedPayloads(_ make: inout Make) async throws {
        let pending = make.pendingURLEncodedPayloads
        make.pendingURLEncodedPayloads = []

        for payload in pending {
            try await payload.resolve(into: &make)
        }
    }

    private func inputs() -> _PropertyInputs {
        .init(
            environment: environment,
            namespaceID: namespaceID,
            seedFactory: seedFactory
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
