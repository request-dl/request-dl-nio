//
// See LICENSE for this package's licensing information.
//

import Logging
import Testing

@testable import RequestDL

struct InternalsTaskLoggerTests {

    private func makeTaskLogger(baseURL: String = "https://apple.com") -> Internals.TaskLogger {
        var requestConfiguration = RequestConfiguration()
        requestConfiguration.baseURL = baseURL

        return Internals.TaskLogger(
            requestConfiguration: requestConfiguration,
            logger: Logger(label: "RequestDL.Tests")
        )!
    }

    @Test
    func initWithoutLoggerReturnsNil() {
        // Given
        let requestConfiguration = RequestConfiguration()

        // When
        let taskLogger = Internals.TaskLogger(requestConfiguration: requestConfiguration, logger: nil)

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
