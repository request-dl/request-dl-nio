/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 `GroupTask` is a task that groups multiple tasks that operate on elements of the same collection type.

 You can use `GroupTask` to create a single task that makes a sequence of requests based on the
 encapsulated `Task`. For each element that should be an `ID` conforming to `Hashable`,
 `GroupTask` will result in a dictionary of results.

 Usage:

 ```swift
 func makeMultipleRequest() async throws -> GroupResult<Int, TaskResult<Data>> {
     try await GroupTask([0, 1, 2, 3]) { index in
         DataTask {
             BaseURL("google.com")
             Path("results")
             Query(index, forKey: "page")
         }
     }
     .result()
 }
 ```

 You can get the result individually or by using the `\.keys`, `\.values` properties of dictionary or by using
 the `subscript` method.
 */
public struct GroupTask<Data: Sequence, Content: Task>: Task where Data.Element: Hashable, Data: Sendable {

    // MARK: - Private properties

    private let data: Data
    private let transform: @Sendable (Data.Element) -> Content

    // MARK: - Inits

    /**
     Initializes a `GroupTask` instance.

     - Parameters:
        - data: The type of the collection that contains the elements.
        - content: The closure map function that transform each element of data into of task.
     */
    public init(_ data: Data, content transform: @escaping @Sendable (Data.Element) -> Content) {
        self.data = data
        self.transform = transform
    }

    // MARK: - Public methods

    /**
      Retrieves the results of the task group that encapsulates the results of each individual task.

      - Returns: A `GroupResult` object that combines the result of each individual task by `ID`.
      - Throws: An error if the operation failed for any reason.
      */
      public func result() async throws -> GroupResult<Data.Element, Content.Element> {
          await withTaskGroup(of: (Data.Element, Result<Content.Element, Error>).self) { group in
              for element in data {
                  group.addTask {
                      do {
                          return (element, .success(try await transform(element).result()))
                      } catch {
                          return (element, .failure(error))
                      }
                  }
              }

              var results = GroupResult<Data.Element, Content.Element>()

              for await (key, value) in group {
                  results[key] = value
              }

              return results
          }
      }
}

/**
 Typealias for a dictionary where the keys are IDs of type `Hashable`, and the values are Results
 of type `Element` or `Error`.
 */
public typealias GroupResult<ID: Hashable, Element: Sendable> = [ID: Result<Element, Error>]
