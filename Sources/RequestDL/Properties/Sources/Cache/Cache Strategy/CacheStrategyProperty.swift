/*
 See LICENSE for this package's licensing information.
*/

import Foundation

private struct CacheStrategyProperty: Property {

    private struct Node: PropertyNode {

        let strategy: CacheStrategy

        func make(_ make: inout Make) async throws {
            make.request.cacheStrategy = strategy
        }
    }

    // MARK: - Internal properties

    var body: Never {
        bodyException()
    }

    let strategy: CacheStrategy

    // MARK: - Internal static methods

    static func _makeProperty(
        property: _GraphValue<CacheStrategyProperty>,
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
        CacheStrategyProperty(strategy: cacheStrategy)
    }
}
