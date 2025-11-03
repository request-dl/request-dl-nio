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

        func uniqueIdentifier(with options: SessionProviderOptions) -> String {
            id
        }
        
        func group(with options: SessionProviderOptions) -> EventLoopGroup {
            _group
        }
    }

    var options: SessionProviderOptions {
        SessionProviderOptions(
            isCompatibleWithNetworkFramework: true
        )
    }

    private var manager: Internals.EventLoopGroupManager?

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
        let sut1 = try await XCTUnwrap(manager).provider(provider, with: options)

        // Then
        XCTAssertTrue(provider.group(with: options) === sut1)
    }

    func testManager_whenRegisterIdentifier_shouldBeResolvedOnlyOnce() async throws {
        // Given
        let provider = CustomProvider()

        // When
        let sut1 = try await XCTUnwrap(manager).provider(provider, with: options)
        let sut2 = try await XCTUnwrap(manager).provider(provider, with: options)

        // Then
        XCTAssertTrue(provider.group(with: options) === sut1)
        XCTAssertTrue(provider.group(with: options) === sut2)
    }

    func testManager_whenRunningInBackground() async throws {
        // Given
        let provider = CustomProvider()

        // When
        let sut = try await _Concurrency.Task.detached(priority: .background) { [manager, options] in
            try await XCTUnwrap(manager).provider(provider, with: options)
        }.value

        // Then
        XCTAssertTrue(sut === provider.group(with: options))
    }
}
