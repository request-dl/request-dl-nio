/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 The RequestBackgroundAdaptor is a property wrapper used in the AppDelegate to
 perform operations after the URLSession calls are finished.

 Example usage:

 ```swift
 @RequestBackgroundAdaptor var backgroundAdaptor
 ```
 */
@propertyWrapper
public struct RequestBackgroundAdaptor {

    public init() {}

    /**
     This property wrapper provides a wrappedValue property that takes a closure with a String
     parameter and returns Void. The set method of the wrappedValue property sets the
     completionHandler property to perform background tasks after the URLSession calls are
     finished.
     */
    public var wrappedValue: (String) -> Void {
        get { fatalError("The 'get' operation for wrapped value is not implemented.") }
        set { BackgroundService.shared.completionHandler = newValue }
    }
}

class BackgroundService {

    static let shared = BackgroundService()

    var completionHandler: ((String) -> Void)?
}
