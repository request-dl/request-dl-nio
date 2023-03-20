/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Modifiers {

    /**
     A modifier to convert `URLSession.AsyncBytes` to `Data` type.

     Use this modifier to convert the bytes returned by a task that produces `URLSession.AsyncBytes`
     to `Data` type.

     Example:

     ```swift
     func getData() async throws -> Data {
         try await BytesTask {
             BaseURL("https://example.com")
         }
         .convertBytesToData()
         .extractPayload()
         .result()
     }
     ```

     - Note: This modifier is available in iOS 15.0+, tvOS 15.0+, watchOS 15.0+, and macOS 12.0+.
     */
    public struct ConvertBytesToData<Content: Task, Output>: TaskModifier {

        private let bytes: (Content.Element) -> AsyncBytes
        private let element: (Content.Element, Data) -> Output

        fileprivate init(
            bytes: @escaping (Content.Element) -> AsyncBytes,
            element: @escaping (Content.Element, Data) -> Output
        ) {
            self.bytes = bytes
            self.element = element
        }

        /**
          Returns a task that converts the bytes returned by a task that produces
         `URLSession.AsyncBytes` to `Data` type.

          - Parameter task: The task that produces `URLSession.AsyncBytes`.
          - Throws: An error if the conversion fails.
          - Returns: The converted data.
          */
        public func task(_ task: Content) async throws -> Output {
            let result = try await task.result()

            var data = Data()

            for try await byte in bytes(result) {
                data.append(byte)
            }

            return element(result, data)
        }
    }
}

extension Task<TaskResult<AsyncBytes>> {

    /**
     Returns a modified task that converts the bytes returned by a task that produces
     `TaskResult<URLSession.AsyncBytes>` to `TaskResult<Data>` type.

     - Returns: A modified task that produces `TaskResult<Data>`.
     */
    public func convertBytesToData() -> ModifiedTask<Modifiers.ConvertBytesToData<Self, TaskResult<Data>>> {
        modify(Modifiers.ConvertBytesToData(
            bytes: \.payload,
            element: {
                TaskResult(
                    head: $0.head,
                    payload: $1
                )
            }
        ))
    }
}

extension Task<AsyncBytes> {

    /**
     Returns a modified task that converts the bytes returned by a task that produces
     `URLSession.AsyncBytes` to `Data` type.

     - Returns: A modified task that produces `Data`.
     */
    public func convertBytesToData() -> ModifiedTask<Modifiers.ConvertBytesToData<Self, Data>> {
        modify(Modifiers.ConvertBytesToData(
            bytes: { $0 },
            element: { $1 }
        ))
    }
}
