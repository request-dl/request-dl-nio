//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL

struct RetryPolicyTests {

    struct TestError: Error {}

    @Test
    func fixedClampsMaxAttemptsToAtLeastOne() {
        // When
        let policy = RetryPolicy.fixed(0)

        // Then
        #expect(policy.maxAttempts == 1)
    }

    @Test
    func fixedUsesTheSameDelayForEveryAttempt() {
        // When
        let policy = RetryPolicy.fixed(5, delay: .seconds(2))

        // Then
        #expect(policy.delay(1) == .seconds(2))
        #expect(policy.delay(2) == .seconds(2))
        #expect(policy.delay(10) == .seconds(2))
    }

    @Test
    func exponentialBackoffGrowsByTheMultiplier() {
        // When
        let policy = RetryPolicy.exponentialBackoff(
            6,
            baseDelay: .seconds(1),
            multiplier: 2,
            maxDelay: .seconds(30)
        )

        // Then
        #expect(policy.delay(1) == .seconds(1))
        #expect(policy.delay(2) == .seconds(2))
        #expect(policy.delay(3) == .seconds(4))
        #expect(policy.delay(4) == .seconds(8))
    }

    @Test
    func exponentialBackoffCapsAtMaxDelay() {
        // When
        let policy = RetryPolicy.exponentialBackoff(
            10,
            baseDelay: .seconds(1),
            multiplier: 2,
            maxDelay: .seconds(10)
        )

        // Then
        #expect(policy.delay(5) == .seconds(10))
        #expect(policy.delay(9) == .seconds(10))
    }

    @Test
    func shouldRetryDefaultsToTrueForAnyError() {
        // When
        let policy = RetryPolicy.fixed(3)

        // Then
        #expect(policy.shouldRetry(TestError()))
    }

    @Test
    func shouldRetryCanBeCustomized() {
        // When
        let policy = RetryPolicy.fixed(3, shouldRetry: { _ in false })

        // Then
        #expect(!policy.shouldRetry(TestError()))
    }
}
