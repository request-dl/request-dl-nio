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
        let provider = CustomProvider()

        // When
        let sut1 = try await XCTUnwrap(manager).provider(provider)

        // Then
        XCTAssertTrue(provider.group() === sut1)
    }

    func testManager_whenRegisterIdentifier_shouldBeResolvedOnlyOnce() async throws {
        // Given
        let provider = CustomProvider()

        // When
        let sut1 = try await XCTUnwrap(manager).provider(provider)
        let sut2 = try await XCTUnwrap(manager).provider(provider)

        // Then
        XCTAssertTrue(provider.group() === sut1)
        XCTAssertTrue(provider.group() === sut2)
    }

    func testManager_whenRunningInBackground() async throws {
        // Given
        let provider = CustomProvider()

        // When
        let sut = await _Concurrency.Task.detached(priority: .background) { [manager] in
            await manager.provider(provider)
        }.value

        // Then
        XCTAssertTrue(sut === provider.group())
    }
}
