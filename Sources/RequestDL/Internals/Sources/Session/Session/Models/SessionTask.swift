/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOCore

struct SessionTask: Sendable {

    // MARK: - Internal properties

    private let response: Internals.AsyncResponse
    private let seed: Internals.TaskSeed

    // MARK: - Inits

    init(
        response: Internals.AsyncResponse,
        seed: Internals.TaskSeed
    ) {
        self.response = response
        self.seed = seed
    }

    init(_ response: Internals.AsyncResponse) {
        self.response = response
        self.seed = .withoutCancellation
    }

    // MARK: - Internal methods

    func callAsFunction() -> AsyncResponse {
        .init(seed: seed, response: response)
    }
}
