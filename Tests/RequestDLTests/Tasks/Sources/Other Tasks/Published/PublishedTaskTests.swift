/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
#if canImport(Combine)
import Combine
@testable import RequestDL

struct PublishedTaskTests {

    enum PublisherResult {
        case success
        case failure
    }

    struct PublisherError: Error {}

    @Test
    func successPublisher() async throws {
        // Given
        var cancellation = Set<AnyCancellable>()
        var isSuccess = false
        let expectation = AsyncSignal()

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
            expectation.signal()
        }.store(in: &cancellation)

        await expectation.wait()

        // Then
        #expect(isSuccess)
    }

    @Test
    func multiplePublishes() async throws {
        // Given
        let subject = PassthroughSubject<Void, Never>()
        var cancellation = Set<AnyCancellable>()
        var isSuccess = true
        let expectation = AsyncSignal()

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
                expectation.signal()
            }.store(in: &cancellation)

        subject.send()

        await expectation.wait()

        // Then
        #expect(isSuccess)
    }
}
#endif
