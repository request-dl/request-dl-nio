/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 Protocol for intercepting and handling results from tasks.

 Define the protocol with a generic type `Element`. The generic type represents the element
 that the task will return.

 Use the `received` method to handle the result of the task with a
 `Result<Element, Error>` parameter.

 - Note: This protocol can be used as a base for creating custom interceptors for tasks.

 Example usage:

 ```swift
 struct MyInterceptor: TaskInterceptor {

     func received(_ result: Result<String, Error>) {
         switch result {
         case .success(let string):
             print("Intercepted task with string result: \(string)")
         case .failure(let error):
             print("Intercepted task with error: \(error.localizedDescription)")
         }
     }
 }
 ```

 - Warning: It is the responsibility of the interceptor to handle errors that may occur
 during the task execution.
 */
public protocol TaskInterceptor<Element> {

    associatedtype Element

    /**
     This method is part of the `TaskInterceptor` protocol, which allows an object to
     intercept and handle the result of a task execution.

     The `received` method is called when the task completes, and receives a `Result`
     object containing either a successful `Element` result or an `Error`.

     - Parameter result: A `Result` object containing either a successful `Element`
     result or an `Error`.
     */
    func received(_ result: Result<Element, Error>)
}
