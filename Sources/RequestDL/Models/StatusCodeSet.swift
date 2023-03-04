//
//  File.swift
//  
//
//  Created by Brenno on 04/03/23.
//

import Foundation

public struct StatusCodeSet: SetAlgebra {

    public typealias Element = StatusCode

    private var statusCodes: Set<StatusCode>


    private init(statusCodes: Set<StatusCode>) {
        self.statusCodes = statusCodes
    }

    public init() {
        self.init(statusCodes: [])
    }

    public init<S: Sequence>(
        _ sequence: __owned S
    ) where S.Element == StatusCode {
        self.init(statusCodes: .init(sequence))
    }

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

extension StatusCodeSet: ExpressibleByArrayLiteral {

    public typealias ArrayLiteralElement = Element

    public init(arrayLiteral elements: Element...) {
        statusCodes = .init(elements)
    }
}

extension StatusCodeSet {

    public static var success: StatusCodeSet {
        .init((200 ..< 300).map {
            StatusCode.custom($0)
        })
    }

    public static var successAndRedirect: StatusCodeSet {
        .init((200 ..< 400).map {
            StatusCode.custom($0)
        })
    }
}
