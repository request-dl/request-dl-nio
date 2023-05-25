/*
 See LICENSE for this package's licensing information.
*/

import Foundation

// swiftlint:disable line_length
private struct CacheConfigurationProperty: Property {

    private struct Node: PropertyNode {

        let memoryCapacity: UInt64
        let diskCapacity: UInt64
        let directory: Internals.CacheConfiguration.Directory

        func make(_ make: inout Make) async throws {
            make.cacheConfiguration.memoryCapacity = memoryCapacity
            make.cacheConfiguration.diskCapacity = diskCapacity
            make.cacheConfiguration.directory = directory
        }
    }

    // MARK: - Internal properties

    var body: Never {
        bodyException()
    }

    let memoryCapacity: UInt64
    let diskCapacity: UInt64
    let directory: Internals.CacheConfiguration.Directory

    // MARK: - Internal static methods

    static func _makeProperty(
        property: _GraphValue<CacheConfigurationProperty>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()
        return .leaf(Node(
            memoryCapacity: property.memoryCapacity,
            diskCapacity: property.diskCapacity,
            directory: property.directory
        ))
    }
}

// MARK: - Property extension

extension Property {

    /**
     Adds a cache configuration to the property with the specified memory and disk capacities.

     - Parameters:
        - memoryCapacity: The maximum memory capacity in bytes for the cache.
        - diskCapacity: The maximum disk capacity in bytes for the cache.
     - Returns: A property with the added cache configuration.
     */
    @PropertyBuilder
    public func cache(
        memoryCapacity: UInt64 = .zero,
        diskCapacity: UInt64 = .zero
    ) -> some Property {
        self
        CacheConfigurationProperty(
            memoryCapacity: memoryCapacity,
            diskCapacity: diskCapacity,
            directory: .main
        )
    }

    /**
     Adds a cache configuration to the property with the specified memory and disk capacities and suite name for disk storage.

     - Parameters:
        - memoryCapacity: The maximum memory capacity in bytes for the cache.
        - diskCapacity: The maximum disk capacity in bytes for the cache.
        - suiteName: The name of the shared user defaults suite for disk storage.
     - Returns: A property with the added cache configuration.
     */
    @PropertyBuilder
    public func cache(
        memoryCapacity: UInt64 = .zero,
        diskCapacity: UInt64 = .zero,
        suiteName: String
    ) -> some Property {
        self
        CacheConfigurationProperty(
            memoryCapacity: memoryCapacity,
            diskCapacity: diskCapacity,
            directory: .custom(suiteName)
        )
    }

    /**
     Adds a cache configuration to the property with the specified memory and disk capacities and file URL for disk storage.

     - Parameters:
        - memoryCapacity: The maximum memory capacity in bytes for the cache.
        - diskCapacity: The maximum disk capacity in bytes for the cache.
        - url: The file URL representing the location for disk storage.
     - Returns: A property with the added cache configuration.
     */
    @PropertyBuilder
    public func cache(
        memoryCapacity: UInt64 = .zero,
        diskCapacity: UInt64 = .zero,
        url: URL
    ) -> some Property {
        self
        CacheConfigurationProperty(
            memoryCapacity: memoryCapacity,
            diskCapacity: diskCapacity,
            directory: .url(url)
        )
    }
}
// swiftlint:enable line_length
