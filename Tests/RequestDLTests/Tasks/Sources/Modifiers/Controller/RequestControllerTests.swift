//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL
@testable import RequestDLInternals

struct RequestControllerTests {

    // MARK: - State

    @Test
    func newController_isNotSuspended() {
        #expect(!RequestController().isSuspended)
    }

    @Test
    func suspendAndResume_areIdempotent() {
        // Given
        let controller = RequestController()

        // When / Then
        controller.suspend()
        controller.suspend()
        #expect(controller.isSuspended)

        controller.resume()
        controller.resume()
        #expect(!controller.isSuspended)
    }

    // MARK: - Attached executions

    @Test
    func suspendAndResume_followedByEveryAttachedExecution() {
        // Given
        let controller = RequestController()
        let first = Internals.TransferControl()
        let second = Internals.TransferControl()

        controller.attach(first)
        controller.attach(second)

        // When
        controller.suspend()

        // Then
        #expect(first.isSuspended)
        #expect(second.isSuspended)

        // When
        controller.resume()

        // Then
        #expect(!first.isSuspended)
        #expect(!second.isSuspended)
    }

    @Test
    func attachingWhileSuspended_startsTheExecutionSuspended() {
        // Given
        let controller = RequestController()
        controller.suspend()

        // When
        let control = Internals.TransferControl()
        controller.attach(control)

        // Then
        #expect(control.isSuspended)

        // When
        controller.resume()

        // Then
        #expect(!control.isSuspended)
    }

    @Test
    func attachingWhileResumed_leavesTheExecutionRunning() {
        // Given
        let controller = RequestController()
        let control = Internals.TransferControl()

        // When
        controller.attach(control)

        // Then
        #expect(!control.isSuspended)
    }

    @Test
    func oneExecution_canFollowSeveralControllers() {
        // Given
        let first = RequestController()
        let second = RequestController()
        let control = Internals.TransferControl()

        first.attach(control)
        second.attach(control)

        // When: whichever ran last decides, as with a single controller.
        first.suspend()
        #expect(control.isSuspended)

        second.resume()
        #expect(!control.isSuspended)
    }

    @Test
    func finishedExecution_isNotRetainedByTheController() {
        // Given
        let controller = RequestController()
        weak var weakControl: Internals.TransferControl?

        do {
            let control = Internals.TransferControl()
            weakControl = control
            controller.attach(control)
        }

        // Then: the execution owns its control; the controller must not keep it alive.
        #expect(weakControl == nil)

        // When: still safe to use with nothing attached.
        controller.suspend()
        controller.resume()

        // Then
        #expect(!controller.isSuspended)
    }
}
