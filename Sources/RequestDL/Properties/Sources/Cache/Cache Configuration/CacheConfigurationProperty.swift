//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.URL
#endif

private struct CacheConfigurationProperty: Property {

    private struct Node: PropertyNode {

        let memoryCapacity: Int64
        let diskCapacity: Int64
        let directory: Internals.CacheConfiguration.Directory
        let encryptionKey: DataCache.EncryptionKey?

        func make(_ make: inout Make) async throws {
            make.cacheConfiguration.memoryCapacity = memoryCapacity
            make.cacheConfiguration.diskCapacity = diskCapacity
            make.cacheConfiguration.directory = directory
            make.cacheConfiguration.encryptionKey = encryptionKey
        }
    }

    // MARK: - Internal properties

    var body: Never {
        bodyException()
    }

    let memoryCapacity: Int64
    let diskCapacity: Int64
    let directory: Internals.CacheConfiguration.Directory
    let encryptionKey: DataCache.EncryptionKey?

    // MARK: - Internal static methods

    static func _makeProperty(
        property: _GraphValue<CacheConfigurationProperty>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()
        return .leaf(
            Node(
                memoryCapacity: property.memoryCapacity,
                diskCapacity: property.diskCapacity,
                directory: property.directory,
                encryptionKey: property.encryptionKey
            )
        )
    }
}

// MARK: - Property extension

extension Property {

    ///
    /// Adds a cache configuration to the property with the specified memory and disk capacities.
    ///
    /// - Parameters:
    ///    - memoryCapacity: The maximum memory capacity in bytes for the cache.
    ///    - diskCapacity: The maximum disk capacity in bytes for the cache.
    ///    - encryptionKey: The key to encrypt the disk tier at rest with. `nil` (the default)
    ///      leaves it unencrypted.
    /// - Returns: A property with the added cache configuration.
    ///
    @PropertyBuilder
    public func cache(
        memoryCapacity: Int64 = .zero,
        diskCapacity: Int64 = .zero,
        encryptionKey: DataCache.EncryptionKey? = nil
    ) -> some Property {
        self
        CacheConfigurationProperty(
            memoryCapacity: memoryCapacity,
            diskCapacity: diskCapacity,
            directory: .main,
            encryptionKey: encryptionKey
        )
    }

    ///
    /// Adds a cache configuration to the property with the specified memory and disk capacities and suite name for disk storage.
    ///
    /// - Parameters:
    ///    - memoryCapacity: The maximum memory capacity in bytes for the cache.
    ///    - diskCapacity: The maximum disk capacity in bytes for the cache.
    ///    - suiteName: The name of the shared user defaults suite for disk storage.
    ///    - encryptionKey: The key to encrypt the disk tier at rest with. `nil` (the default)
    ///      leaves it unencrypted.
    /// - Returns: A property with the added cache configuration.
    ///
    @PropertyBuilder
    public func cache(
        memoryCapacity: Int64 = .zero,
        diskCapacity: Int64 = .zero,
        suiteName: String,
        encryptionKey: DataCache.EncryptionKey? = nil
    ) -> some Property {
        self
        CacheConfigurationProperty(
            memoryCapacity: memoryCapacity,
            diskCapacity: diskCapacity,
            directory: .custom(suiteName),
            encryptionKey: encryptionKey
        )
    }

    ///
    /// Adds a cache configuration to the property with the specified memory and disk capacities and file URL for disk storage.
    ///
    /// - Parameters:
    ///    - memoryCapacity: The maximum memory capacity in bytes for the cache.
    ///    - diskCapacity: The maximum disk capacity in bytes for the cache.
    ///    - url: The file URL representing the location for disk storage.
    ///    - encryptionKey: The key to encrypt the disk tier at rest with. `nil` (the default)
    ///      leaves it unencrypted.
    /// - Returns: A property with the added cache configuration.
    ///
    @PropertyBuilder
    public func cache(
        memoryCapacity: Int64 = .zero,
        diskCapacity: Int64 = .zero,
        url: URL,
        encryptionKey: DataCache.EncryptionKey? = nil
    ) -> some Property {
        self
        CacheConfigurationProperty(
            memoryCapacity: memoryCapacity,
            diskCapacity: diskCapacity,
            directory: .url(url),
            encryptionKey: encryptionKey
        )
    }
}
