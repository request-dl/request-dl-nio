/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOCore

struct SessionTask: Sendable {

    // MARK: - Private properties

    private let seed: Internals.TaskSeed
    private let response: Internals.AsyncResponse

    // MARK: - Inits

    init(
        seed: Internals.TaskSeed,
        response: Internals.AsyncResponse
    ) {
        self.seed = seed
        self.response = response
    }

    init(_ response: Internals.AsyncResponse) {
        self.response = response
        self.seed = .withoutCancellation
    }

    // MARK: - Internal methods

    func callAsFunction() -> AsyncResponse {
        AsyncResponse(
            seed: seed,
            response: response
        )
    }
}
