/*
 See LICENSE for this package's licensing information.
*/

import XCTest
import NIOPosix
@testable import RequestDLInternals

class EventLoopManagerTests: XCTestCase {

    private var manager: EventLoopGroupManager!

    override func setUp() async throws {
        try await super.setUp()
        manager = EventLoopGroupManager()
    }

    override func tearDown() async throws {
        try await super.tearDown()
        manager = nil
    }

    func testManager_whenRegisterGroup_shouldBeResolved() async throws {
        // Given
        let id = "test"
        var group: EventLoopGroup! = MultiThreadedEventLoopGroup(numberOfThreads: 1)

        // When
        weak var reference = group

        try await manager.client(
            id: id,
            factory: { group },
            configuration: .init()
        ).shutdown()

        // Then
        group = nil

        XCTAssertNotNil(reference)
    }

    func testManager_whenRegisterIdentifier_shouldBeResolvedOnlyOnce() async throws {
        // Given
        let id = "test"
        let group: () -> EventLoopGroup = {
            MultiThreadedEventLoopGroup(numberOfThreads: 1)
        }

        // When
        let client1 = await manager.client(
            id: id,
            factory: group,
            configuration: .init()
        )

        let client2 = await manager.client(
            id: id,
            factory: group,
            configuration: .init()
        )

        try await client1.shutdown()
        try await client2.shutdown()

        // Then
        XCTAssertTrue(client1.eventLoopGroup === client2.eventLoopGroup)
    }
}
