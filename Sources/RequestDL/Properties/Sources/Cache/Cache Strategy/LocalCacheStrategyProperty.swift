/*
 See LICENSE for this package's licensing information.
*/

import Foundation

private struct LocalCacheStrategyProperty: Property {

    private struct Node: PropertyNode {

        let strategy: CacheStrategy

        func make(_ make: inout Make) async throws {
            make.request.localCacheStrategy = strategy
        }
    }

    // MARK: - Internal properties

    var body: Never {
        bodyException()
    }

    let strategy: CacheStrategy

    // MARK: - Internal static methods

    static func _makeProperty(
        property: _GraphValue<LocalCacheStrategyProperty>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()
        return .leaf(Node(strategy: property.strategy))
    }
}

// MARK: - Property extension

extension Property {

    /**
     Adds a cache strategy to the property using the specified cache strategy.
     
     - Parameter cacheStrategy: The cache strategy to be added to the property.
     - Returns: A property with the added cache strategy.
     */
    @PropertyBuilder
    public func cacheStrategy(_ cacheStrategy: CacheStrategy) -> some Property {
        self
        LocalCacheStrategyProperty(strategy: cacheStrategy)
    }
}
