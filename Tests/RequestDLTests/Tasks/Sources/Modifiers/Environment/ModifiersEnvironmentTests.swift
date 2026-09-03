//
// See LICENSE for this package's licensing information.
//

import Testing

@_spi(Private) @testable import RequestDL

struct ModifiersEnvironmentTests {

    struct NumberTask: RequestTask {

        @RequestEnvironment(\.number) var number

        func result() async throws -> Int {
            number
        }
    }

    struct OuterTask: RequestTask {

        func result() async throws -> Int {
            // Deliberately calls the plain `result()`, not the SPI `_result(environment:)` --
            // this is what an unrelated `RequestTask` constructed inside another task's body
            // would do, with no way to (and no reason to) reach for the SPI entry point.
            try await NumberTask().result()
        }
    }

    @Test
    func environment_whenNotSet() async throws {
        // Given
        let numberTask = NumberTask()

        // When
        let value = try await numberTask.result()

        // Then
        #expect(value == 1)
    }

    @Test
    func environment_whenUpdatedWithValue() async throws {
        // Given
        let number = 2
        let numberTask = NumberTask()

        // When
        let value =
            try await numberTask
            .environment(\.number, number)
            .result()

        // Then
        #expect(value == number)
    }

    @Test
    func environment_whenSetOnAnOuterTask_doesNotLeakIntoAnUnrelatedNestedTask() async throws {
        // Given
        let outerTask = OuterTask()

        // When
        let value =
            try await outerTask
            .environment(\.number, 2)
            .result()

        // Then -- `NumberTask`, constructed fresh inside `OuterTask.result()`, never received
        // `OuterTask`'s own `.environment(\.number, 2)`, so it falls back to the key's default.
        #expect(value == 1)
    }
}

private struct NumberKey: RequestEnvironmentKey {
    static let defaultValue = 1
}

extension RequestEnvironmentValues {

    fileprivate var number: Int {
        get { self[NumberKey.self] }
        set { self[NumberKey.self] = newValue }
    }
}
