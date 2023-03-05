//
//  RequestBackgroundAdaptor.swift
//
//  MIT License
//
//  Copyright (c) RequestDL
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

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
