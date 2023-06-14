/*
 See LICENSE for this package's licensing information.
*/

#if canImport(Darwin)
import Foundation
#else
@preconcurrency import Foundation
#endif

extension Modifiers {

    /// A request task modifier that collects and combines individual bytes into a consolidated `Data` object.
    public struct CollectData<Input: Sendable, Output: Sendable>: RequestTaskModifier {

        // MARK: - Private properties

        private let transform: @Sendable (Input) async throws -> Output

        // MARK: - Inits

        fileprivate init() where Input == AsyncResponse, Output == TaskResult<Data> {
            transform = {
                let result = try await $0.collect()
                return try await .init(
                    head: result.head,
                    payload: result.payload.collect()
                )
            }
        }

        fileprivate init() where Input == TaskResult<AsyncBytes>, Output == TaskResult<Data> {
            transform = {
                try await .init(
                    head: $0.head,
                    payload: $0.payload.collect()
                )
            }
        }

        fileprivate init() where Input == AsyncBytes, Output == Data {
            transform = {
                try await $0.collect()
            }
        }

        // MARK: - Public methods

        /**
         Combines individual bytes into `Data` object.

         - Parameter task: The request task to modify.
         - Returns: The task result.
         - Throws: An error if the modification fails.
         */
        public func body(_ task: Content) async throws -> Output {
            try await transform(task.result())
        }
    }
}

// MARK: - RequestTask extension

// swiftlint:disable line_length
extension RequestTask<AsyncResponse> {

    /// Returns a modified request task that collects and combines the individual bytes into a consolidated `Data` object.
    public func collectData() -> ModifiedRequestTask<Modifiers.CollectData<Element, TaskResult<Data>>>  {
        modifier(Modifiers.CollectData())
    }
}

extension RequestTask<TaskResult<AsyncBytes>> {

    /// Returns a modified request task that collects and combines the individual bytes into a consolidated `Data` object.
    public func collectData() -> ModifiedRequestTask<Modifiers.CollectData<Element, TaskResult<Data>>> {
        modifier(Modifiers.CollectData())
    }
}

extension RequestTask<AsyncBytes> {

    /// Returns a modified request task that collects and combines the individual bytes into a consolidated `Data` object.
    public func collectData() -> ModifiedRequestTask<Modifiers.CollectData<Element, Data>> {
        modifier(Modifiers.CollectData())
    }
}
// swiftlint:enable line_length
