/*
 See LICENSE for this package's licensing information.
*/

import XCTest
import NIOCore
import NIOPosix
@testable import RequestDL

class InternalsEventLoopManagerTests: XCTestCase {

    struct CustomProvider: SessionProvider {

        let id = "test"
        private let _group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

        func group() -> EventLoopGroup {
            _group
        }
    }

    private var manager: Internals.EventLoopGroupManager!

    override func setUp() async throws {
        try await super.setUp()
        manager = Internals.EventLoopGroupManager()
    }

    override func tearDown() async throws {
        try await super.tearDown()
        manager = nil
    }

    func testManager_whenRegisterGroup_shouldBeResolved() async throws {
        // Given
        var provider: CustomProvider! = CustomProvider()

        // When
        weak var reference = provider.group()

        try await manager.client(
            .init(),
            for: provider
        ).shutdown()

        // Then
        provider = nil

        XCTAssertNotNil(reference)
    }

    func testManager_whenRegisterIdentifier_shouldBeResolvedOnlyOnce() async throws {
        // Given
        let provider = CustomProvider()

        // When
        let client1 = await manager.client(
            .init(),
            for: provider
        )

        let client2 = await manager.client(
            .init(),
            for: provider
        )

        try await client1.shutdown()
        try await client2.shutdown()

        // Then
        XCTAssertTrue(client1.eventLoopGroup === client2.eventLoopGroup)
    }

    func testManager_whenCustomGroup_shouldBeValid() async throws {
        // Given
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

        // When
        let client = await manager.client(
            .init(),
            for: .custom(group)
        )

        try await client.shutdown()

        // Then
        XCTAssertTrue(client.eventLoopGroup === group)
    }
}
