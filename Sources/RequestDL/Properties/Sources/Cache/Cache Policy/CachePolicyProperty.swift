//
// See LICENSE for this package's licensing information.
//

private struct CachePolicyProperty: Property {

    private struct Node: PropertyNode {

        let policy: DataCache.Policy.Set

        func make(_ make: inout Make) async throws {
            make.requestConfiguration.cachePolicy = policy
        }
    }

    // MARK: - Internal properties

    var body: Never {
        bodyException()
    }

    let policy: DataCache.Policy.Set

    // MARK: - Internal static methods

    static func _makeProperty(
        property: _GraphValue<CachePolicyProperty>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()
        return .leaf(Node(policy: property.policy))
    }
}

// MARK: - Property extension

extension Property {

    ///
    /// Adds a cache policy to the request using the specified cache policy set.
    ///
    /// A response is stored as it downloads. If the cache writer falls more than 16 MiB behind
    /// the download (a body larger than that, on a fast network, while the ``DataCache`` is busy),
    /// the response is not cached: the request still succeeds and returns the whole body, nothing
    /// is stored, and a warning is logged. The next request for the same URL is then a cache miss.
    ///
    /// A response that nothing proves arrived whole is not stored. On `.urlSession` that is every
    /// response without a `Content-Length` (chunked, in practice): CFNetwork reports one cut
    /// between two chunks as complete. It is delivered to the caller as usual, and the next request
    /// for that URL goes to the network. The `.nio` executors end a chunked body with a terminator
    /// and cache it as usual, and ``Property/cacheCompletenessProbe(_:)`` lets `.urlSession` ask the
    /// server first. See <doc:Cache-support>.
    ///
    /// - Parameter cachePolicy: The cache policy set to be added to the request.
    /// - Returns: A property with the added cache policy.
    ///
    @PropertyBuilder
    public func cachePolicy(_ cachePolicy: DataCache.Policy.Set) -> some Property {
        self
        CachePolicyProperty(policy: cachePolicy)
    }
}
