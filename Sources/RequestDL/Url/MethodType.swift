//
//  MethodType.swift
//
//  MIT License
//
//  Copyright (c) 2022 RequestDL
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

/// Define constants for the action to be performed on the endpoint
public enum MethodType: String, CaseIterable {

    /// Defines a GET operation
    case get = "GET"

    /// Defines an HEAD operation
    case head = "HEAD"

    /// Defines a POST operation
    case post = "POST"

    /// Defines a PUT operation
    case put = "PUT"

    /// Defines a DELETE operation
    case delete = "DELETE"

    /// Defines a CONNECT operation
    case connect = "CONNECT"

    /// Defines a OPTIONS operation
    case options = "OPTIONS"

    /// Defines a TRACE operation
    case trace = "TRACE"

    /// Defines a PATCH operation
    case patch = "PATCH"
}
