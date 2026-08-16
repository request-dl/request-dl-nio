//
// See LICENSE for this package's licensing information.
//

import Logging
import Testing

@testable import RequestDLInternals

struct InternalsTaskLoggerTests {

    private func makeTaskLogger(
        baseURL: String = "https://apple.com",
        pathComponents: [String] = []
    ) -> Internals.TaskLogger {
        Internals.TaskLogger(
            baseURL: baseURL,
            pathComponents: pathComponents,
            logger: Logger(label: "RequestDL.Tests")
        )!
    }

    @Test
    func initWithoutLoggerReturnsNil() {
        // When
        let taskLogger = Internals.TaskLogger(baseURL: "https://apple.com", pathComponents: [], logger: nil)

        // Then
        #expect(taskLogger == nil)
    }

    @Test
    func equalityComparesAllStoredFields() {
        // Given
        let taskLogger = makeTaskLogger()

        // Then
        // Every `TaskLogger` gets a fresh UUID at construction, so two independently-built
        // instances are never equal even with the same base URL.
        #expect(taskLogger == taskLogger)
        #expect(taskLogger != makeTaskLogger())
    }

    @Test
    func hashableAllowsUseAsSetMember() {
        // Given
        let taskLogger = makeTaskLogger()

        // When
        let set: Set<Internals.TaskLogger> = [taskLogger, taskLogger, makeTaskLogger()]

        // Then
        #expect(set.count == 2)
    }
}
