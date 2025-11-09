/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct StatusCodeSetTests {

    @Test
    func initSet_isEmpty() async throws {
        let set = StatusCodeSet()
        #expect(set.isEmpty)
    }

    @Test
    func initWithSequence() async throws {
        let sequence: [StatusCode] = [.ok, .created, .accepted]
        let set = StatusCodeSet(sequence)
        #expect(set.count == 3)
        #expect(set.contains(.ok))
        #expect(set.contains(.created))
        #expect(set.contains(.accepted))
    }

    @Test
    func union() async throws {
        let set1: StatusCodeSet = [.ok, .created, .badRequest]
        let set2: StatusCodeSet = [400, 401, 404]
        let expectedResult: StatusCodeSet = [200, 201, 400, 401, 404]

        let result = set1.union(set2)

        #expect(result == expectedResult)
    }

    @Test
    func intersection() async throws {
        let set1 = StatusCodeSet([.ok, .created, .noContent])
        let set2 = StatusCodeSet([.ok, .badRequest, .forbidden])

        let intersection = set1.intersection(set2)

        #expect(intersection == [.ok])

        let set3 = StatusCodeSet([.ok, .created])
        let set4 = StatusCodeSet([.ok, .created])

        let intersection2 = set3.intersection(set4)

        #expect(intersection2 == [.ok, .created])

        let set5 = StatusCodeSet([.ok, .created, .noContent])
        let set6 = StatusCodeSet([.notFound, .badRequest, .forbidden])

        let intersection3 = set5.intersection(set6)

        #expect(intersection3.isEmpty)
    }

    @Test
    func symmetricDifference() async throws {
        let set1 = StatusCodeSet([200, 201, 204])
        let set2 = StatusCodeSet([200, 400, 404])

        let symmetricDifference = set1.symmetricDifference(set2)

        #expect(symmetricDifference == [201, 204, 400, 404])
    }

    @Test
    func formUnion() async throws {
        var set1 = StatusCodeSet([200, 201, 202])
        let set2 = StatusCodeSet([201, 203])

        set1.formUnion(set2)

        #expect(set1 == [200, 201, 202, 203])
    }

    @Test
    func formIntersection() async throws {
        var set1 = StatusCodeSet([200, 201, 202])
        let set2 = StatusCodeSet([201, 203])

        set1.formIntersection(set2)

        #expect(set1 == [201])
    }

    @Test
    func formSymmetricDifference() async throws {
        var statusCodeSet = StatusCodeSet([200, 201, 202, 203])
        let other = StatusCodeSet([201, 202, 204, 205])

        statusCodeSet.formSymmetricDifference(other)

        #expect(statusCodeSet == [200, 203, 204, 205])
    }

    @Test
    func contains() async throws {
        let statusCodeSet = StatusCodeSet([200, 201, 202, 203])
        #expect(statusCodeSet.contains(200))
        #expect(statusCodeSet.contains(202))
        #expect(!statusCodeSet.contains(204))
    }

    @Test
    func insert() async throws {
        var set = StatusCodeSet([.ok, .created])
        let result = set.insert(.noContent)
        #expect(result.inserted)
        #expect(result.memberAfterInsert == .noContent)
        #expect(set.contains(.noContent))
    }

    @Test
    func remove() async throws {
        var set = StatusCodeSet([.ok, .created])
        let result = set.remove(.created)
        #expect(result == .created)
        #expect(!set.contains(.created))
    }

    @Test
    func update() async throws {
        var set = StatusCodeSet([.ok, .created])
        let result = set.update(with: .created)
        #expect(result == .created)
        #expect(set == [.ok, .created])
    }

    @Test
    func success() async throws {
        let success = StatusCodeSet.success
        #expect(success.contains(.ok))
        #expect(success.contains(.created))
        #expect(success.contains(.accepted))
        #expect(success.contains(.nonAuthoritativeInformation))
        #expect(success.contains(.noContent))
        #expect(success.contains(.resetContent))
        #expect(success.contains(.partialContent))
        #expect(success.contains(.multiStatus))
        #expect(success.contains(.alreadyReported))
        #expect(success.contains(.imUsed))
    }

    @Test
    func successAndRedirect() async throws {
        let successAndRedirect = StatusCodeSet.successAndRedirect
        #expect(successAndRedirect.contains(.ok))
        #expect(successAndRedirect.contains(.created))
        #expect(successAndRedirect.contains(.accepted))
        #expect(successAndRedirect.contains(.nonAuthoritativeInformation))
        #expect(successAndRedirect.contains(.noContent))
        #expect(successAndRedirect.contains(.resetContent))
        #expect(successAndRedirect.contains(.partialContent))
        #expect(successAndRedirect.contains(.multiStatus))
        #expect(successAndRedirect.contains(.alreadyReported))
        #expect(successAndRedirect.contains(.imUsed))
        #expect(successAndRedirect.contains(.multipleChoices))
        #expect(successAndRedirect.contains(.movedPermanently))
        #expect(successAndRedirect.contains(.found))
        #expect(successAndRedirect.contains(.seeOther))
        #expect(successAndRedirect.contains(.notModified))
        #expect(successAndRedirect.contains(.useProxy))
        #expect(successAndRedirect.contains(.temporaryRedirect))
        #expect(successAndRedirect.contains(.permanentRedirect))
    }
}
