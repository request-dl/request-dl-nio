//
//  ReverseFormData.swift
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

import XCTest
@testable import RequestDL

struct ReverseFormData {

    let items: [FormDataItem]

    init(_ data: Data, boundary: String) {
        let rawData = String(data: data, encoding: .utf8) ?? "nil"
        var items: [FormDataItem] = []
        var item: FormDataItem?
        var state: State?
        var eof = false

        for line in rawData.split(separator: "\r\n", omittingEmptySubsequences: false) {
            var error = false

            if eof {
                error = true
            }

            switch line {
            case "--\(boundary)":
                guard case .none = state else {
                    error = true
                    break
                }

                item = FormDataItem()
                state = .headers
            case "":
                guard case .headers? = state else {
                    error = true
                    break
                }

                state = .payload
            case "--\(boundary)--":
                eof = true
            default:
                if var mutableItem = item {
                    if case .headers = state {
                        var contents = line.split(separator: ":")
                        let key = contents.removeFirst()
                        var value = contents.joined(separator: ":")

                        if value[value.startIndex] != " " {
                            error = true
                        } else {
                            value.removeFirst()
                        }

                        mutableItem.headers = [String(key): value]
                            .merging(mutableItem.headers ?? [:]) { lhs, rhs in lhs }

                        item = mutableItem
                        break
                    }

                    if case .payload = state {
                        mutableItem.data = String(line)
                        items.append(mutableItem)
                        state = nil
                        item = nil
                        break
                    }
                }

                error = true
            }

            if error {
                self.items = []
                return
            }
        }

        self.items = items
    }
}

extension ReverseFormData {

    struct FormDataItem {
        fileprivate(set) var headers: [String: String]?
        fileprivate(set) var data: String?
    }

    private enum State {
        case beginning
        case headers
        case payload
    }
}

extension ReverseFormData {

    static func extractBoundary(_ string: String?) -> String? {
        let boundary = string?
            .split(separator: ";")
            .last?
            .split(separator: "=")
            .last

        return boundary.map { "\($0)" }?.trimmingCharacters(in: .init(charactersIn: "\""))
    }
}
