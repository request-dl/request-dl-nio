/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 A error type representing a validation error due to an unexpected HTTP status code.
 Conforms to the `TaskError` protocol.

 Usage:

 ```swift
 do {
     let result = try await DataTask {
         BaseURL("apple.com")
     }
     .acceptOnlyStatusCode(.successAndRedirect)
     .result()
     // use validated result
 } catch let error as InvalidStatusCodeError<Data> {
     // handle validation error
 }
 ```
*/
public struct InvalidStatusCodeError<Element>: TaskError {

    /// The data that caused the validation error.
    public let data: Element
}
