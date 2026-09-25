//
// See LICENSE for this package's licensing information.
//

import SwiftAsyncStream
import Testing

@testable import RequestDL

struct ModifiedRequestTaskTests {

    struct Modified<Input: Sendable>: RequestTaskModifier {

        let callback: @Sendable () -> Void

        func body(_ task: Content) async throws -> Input {
            callback()
            return try await task.result()
        }
    }

    @Test
    func modified() async throws {
        // Given
        let taskModified = InlineProperty(wrappedValue: false)

        // When
        _ = try await MockedTask {
            BaseURL("localhost")
        }
        .modifier(
            Modified {
                taskModified.wrappedValue = true
            }
        )
        .result()

        // Then
        #expect(taskModified.wrappedValue)
    }

    fileprivate struct FlagKey: RequestEnvironmentKey {
        static let defaultValue = false
    }

    fileprivate struct FlagReadingModifier<Input: Sendable>: RequestTaskModifier {

        @RequestEnvironment(\.modifierFlag) var flag

        let callback: @Sendable (Bool) -> Void

        func body(_ task: Content) async throws -> Input {
            callback(flag)
            return try await task.result()
        }
    }

    @Test
    func modifier_readsEnvironmentSetOnTheSameChain() async throws {
        // Given: the environment is set on the same task chain as the modifier itself, not just
        // visible to the wrapped task -- `Modifiers.Environment.body` never updated the modifier's
        // own `@RequestEnvironment` properties, only the `Content` passed down to the inner task.
        let observedFlag = InlineProperty(wrappedValue: false)

        // When
        _ = try await MockedTask {
            BaseURL("localhost")
        }
        .modifier(
            FlagReadingModifier {
                observedFlag.wrappedValue = $0
            }
        )
        .environment(\.modifierFlag, true)
        .result()

        // Then
        #expect(observedFlag.wrappedValue)
    }
}

extension RequestEnvironmentValues {

    fileprivate var modifierFlag: Bool {
        get { self[ModifiedRequestTaskTests.FlagKey.self] }
        set { self[ModifiedRequestTaskTests.FlagKey.self] = newValue }
    }
}
