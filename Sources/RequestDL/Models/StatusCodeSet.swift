//
//  StatusCodeSet.swift
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

/// A set of HTTP status codes.
public struct StatusCodeSet: SetAlgebra {

    public typealias Element = StatusCode

    private var statusCodes: Set<StatusCode>

    private init(statusCodes: Set<StatusCode>) {
        self.statusCodes = statusCodes
    }

    /// Creates an empty set
    public init() {
        self.init(statusCodes: [])
    }

    public init<S: Sequence>(
        _ sequence: __owned S
    ) where S.Element == StatusCode {
        self.init(statusCodes: .init(sequence))
    }
}

extension StatusCodeSet {

    public func union(_ other: __owned StatusCodeSet) -> StatusCodeSet {
        .init(statusCodes: statusCodes.union(other.statusCodes))
    }

    public func intersection(_ other: StatusCodeSet) -> StatusCodeSet {
        .init(statusCodes: statusCodes.intersection(other.statusCodes))
    }

    public func symmetricDifference(_ other: __owned StatusCodeSet) -> StatusCodeSet {
        .init(statusCodes: statusCodes.symmetricDifference(other.statusCodes))
    }

    public mutating func formUnion(_ other: __owned StatusCodeSet) {
        statusCodes.formUnion(other.statusCodes)
    }

    public mutating func formIntersection(_ other: StatusCodeSet) {
        statusCodes.formIntersection(other.statusCodes)
    }

    public mutating func formSymmetricDifference(_ other: __owned StatusCodeSet) {
        statusCodes.formSymmetricDifference(other.statusCodes)
    }

    public func contains(_ member: StatusCode) -> Bool {
        statusCodes.contains(member)
    }

    public mutating func insert(
        _ newMember: __owned StatusCode
    ) -> (inserted: Bool, memberAfterInsert: StatusCode) {
        statusCodes.insert(newMember)
    }

    public mutating func remove(_ member: StatusCode) -> StatusCode? {
        statusCodes.remove(member)
    }

    public mutating func update(with newMember: __owned StatusCode) -> StatusCode? {
        statusCodes.update(with: newMember)
    }
}

extension StatusCodeSet {

    /// A set containing all HTTP status codes in the range of 200 to 299.
    public static let success: StatusCodeSet = {
        StatusCodeSet((200 ..< 300).map(StatusCode.init(_:)))
    }()

    /// A set containing all HTTP status codes in the range of 200 to 399.
    public static let successAndRedirect: StatusCodeSet = {
        StatusCodeSet((200 ..< 400).map(StatusCode.init(_:)))
    }()
}
