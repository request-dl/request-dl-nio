/*
 See LICENSE for this package's licensing information.
*/

import Foundation

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

    /**
     Adds a cache policy to the request using the specified cache policy set.

     - Parameter cachePolicy: The cache policy set to be added to the request.
     - Returns: A property with the added cache policy.
     */
    @PropertyBuilder
    public func cachePolicy(_ cachePolity: DataCache.Policy.Set) -> some Property {
        self
        CachePolicyProperty(policy: cachePolity)
    }
}
