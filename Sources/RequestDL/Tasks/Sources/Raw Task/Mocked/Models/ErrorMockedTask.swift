//
// See LICENSE for this package's licensing information.
//

struct ErrorMockedTask: MockedTaskPayload {

    // MARK: - Internal properties

    let error: Error
    let delay: UnitTime

    // MARK: - Internal methods

    func result(_ environment: RequestEnvironmentValues) async throws -> AsyncResponse {
        if delay > .zero {
            try await Task.sleep(nanoseconds: UInt64(delay.nanoseconds))
        }

        throw error
    }
}
