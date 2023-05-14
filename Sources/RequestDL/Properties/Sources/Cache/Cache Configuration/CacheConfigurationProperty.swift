/*
 See LICENSE for this package's licensing information.
*/

import Foundation

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

    @PropertyBuilder
    public func cache(
        memoryCapacity: UInt64
    ) -> some Property {
        self
        cache(
            memoryCapacity: memoryCapacity,
            diskCapacity: .zero
        )
    }

    @PropertyBuilder
    public func cache(
        diskCapacity: UInt64
    ) -> some Property {
        self
        cache(
            memoryCapacity: .zero,
            diskCapacity: diskCapacity
        )
    }

    @PropertyBuilder
    public func cache(
        memoryCapacity: UInt64,
        diskCapacity: UInt64
    ) -> some Property {
        self
        CacheConfigurationProperty(
            memoryCapacity: memoryCapacity,
            diskCapacity: diskCapacity,
            directory: .main
        )
    }

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
