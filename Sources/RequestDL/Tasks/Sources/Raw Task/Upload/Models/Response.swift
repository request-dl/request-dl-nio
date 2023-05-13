/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 An enumeration that represents the steps of an asynchronous response.

 `Response` provides options to represent different steps of an asynchronous response in Swift.

 - `upload`: Represents an upload step with an associated progress value.
 - `download`: Represents a download step with an associated `ResponseHead` object and an
 `AsyncBytes` object.
 */
public enum Response: Hashable {

    /**
     Represents an upload step with an associated progress value.

     - Parameter Int: An integer value representing the length of bytes uploaded.
     */
    case upload(Int)

    /**
     Represents a download step with an associated `ResponseHead` object and an `AsyncBytes`
     object.

     - Parameters:
        - head: A `ResponseHead` object representing the response head.
        - body: An `AsyncBytes` object representing the response body.
     */
    case download(ResponseHead, AsyncBytes)
}
