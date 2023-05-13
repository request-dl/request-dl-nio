/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/// A set of HTTP status codes.
public struct StatusCodeSet: SetAlgebra, Sendable {

    public typealias Element = StatusCode

    // MARK: - Public static properties

    /// A set containing all HTTP status codes in the range of 200 to 299.
    public static let success: StatusCodeSet = {
        StatusCodeSet((200 ..< 300).map(StatusCode.init(_:)))
    }()

    /// A set containing all HTTP status codes in the range of 200 to 399.
    public static let successAndRedirect: StatusCodeSet = {
        StatusCodeSet((200 ..< 400).map(StatusCode.init(_:)))
    }()

    // MARK: - Public properties

    public var count: Int {
        statusCodes.count
    }

    // MARK: - Private properties

    private var statusCodes: Set<StatusCode>

    // MARK: - Inits

    /// Creates an empty set
    public init() {
        self.init(statusCodes: [])
    }

    public init<S: Sequence>(
        _ sequence: __owned S
    ) where S.Element == StatusCode {
        self.init(statusCodes: .init(sequence))
    }

    private init(statusCodes: Set<StatusCode>) {
        self.statusCodes = statusCodes
    }

    // MARK: - Public methods

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
