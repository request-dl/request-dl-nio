/*
 See LICENSE for this package's licensing information.
*/

import XCTest
#if canImport(Combine)
import Combine
@testable import RequestDL

class PublishedTaskTests: XCTestCase {

    enum PublisherResult {
        case success
        case failure
    }

    struct PublisherError: Error {}

    func testSuccessPublisher() async throws {
        // Given
        var cancellation = Set<AnyCancellable>()
        var isSuccess = false
        let expectation = expectation(description: "publisher")

        // When
        MockedTask {
            BaseURL("localhost")
        }
        .collectData()
        .publisher()
        .map { _ in
            PublisherResult.success
        }
        .replaceError(with: .failure)
        .sink {
            isSuccess = $0 == .success
            expectation.fulfill()
        }.store(in: &cancellation)

        await _fulfillment(of: [expectation], timeout: 3.0)

        // Then
        XCTAssertTrue(isSuccess)
    }

    func testMultiplePublishes() async throws {
        // Given
        let subject = PassthroughSubject<Void, Never>()
        var cancellation = Set<AnyCancellable>()
        var isSuccess = true
        let expectation = expectation(description: "publisher")

        expectation.expectedFulfillmentCount = 2

        // When
        subject
            .flatMap {
                MockedTask {
                    BaseURL("localhost")
                }
                .collectData()
                .publisher()
                .map { _ in
                    PublisherResult.success
                }
                .replaceError(with: .failure)
            }
            .sink {
                isSuccess = isSuccess && $0 == .success
                expectation.fulfill()
            }.store(in: &cancellation)

        subject.send()
        subject.send()

        await _fulfillment(of: [expectation], timeout: 3.0)

        // Then
        XCTAssertTrue(isSuccess)
    }
}
#endif
