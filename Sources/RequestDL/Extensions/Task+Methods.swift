//
//  Task+Methods.swift
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

extension Task {

    /**
     A convenience method to send a simple ping request to the server and wait for the response.

     - Parameters:
        - times: Number of times the ping should be sent. Default value is 1.
        - debug: A flag to indicate whether or not to print debug information. Default value is true.

     - Throws: An error if the ping request fails.

     - Returns: Nothing. This function only waits for the server to respond to the ping request.
     */
    public func ping(_ times: Int = 1, debug: Bool = true) async throws {
        guard times > 0 else {
            fatalError()
        }

        for index in 0 ..< times {
            if debug {
                print("[RequestDL] Pinging \(index + 1) started")
            }

            let time = Date()
            _ = try await response()

            if debug {
                let interval = Date().timeIntervalSince(time)

                print("[RequestDL] Pinging \(index + 1) success \(String(format: "%0.3f", interval))s")
            }
        }
    }
}
