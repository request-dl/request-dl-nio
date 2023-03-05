//
//  StatusCodeSetTests.swift
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

final class StatusCodeSetTests: XCTestCase {

    func testInit() {
        let set = StatusCodeSet()
        XCTAssertTrue(set.isEmpty)
    }

    func testInitWithSequence() {
        let sequence: [StatusCode] = [.ok, .created, .accepted]
        let set = StatusCodeSet(sequence)
        XCTAssertEqual(set.count, 3)
        XCTAssertTrue(set.contains(.ok))
        XCTAssertTrue(set.contains(.created))
        XCTAssertTrue(set.contains(.accepted))
    }

    func testUnion() {
        let set1: StatusCodeSet = [.ok, .created, .badRequest]
        let set2: StatusCodeSet = [400, 401, 404]
        let expectedResult: StatusCodeSet = [200, 201, 400, 401, 404]

        let result = set1.union(set2)

        XCTAssertEqual(result, expectedResult)
    }

    func testIntersection() {
        let set1 = StatusCodeSet([.ok, .created, .noContent])
        let set2 = StatusCodeSet([.ok, .badRequest, .forbidden])

        let intersection = set1.intersection(set2)

        XCTAssertEqual(intersection, [.ok])

        let set3 = StatusCodeSet([.ok, .created])
        let set4 = StatusCodeSet([.ok, .created])

        let intersection2 = set3.intersection(set4)

        XCTAssertEqual(intersection2, [.ok, .created])

        let set5 = StatusCodeSet([.ok, .created, .noContent])
        let set6 = StatusCodeSet([.notFound, .badRequest, .forbidden])

        let intersection3 = set5.intersection(set6)

        XCTAssertTrue(intersection3.isEmpty)
    }

    func testSymmetricDifference() {
        let set1 = StatusCodeSet([200, 201, 204])
        let set2 = StatusCodeSet([200, 400, 404])

        let symmetricDifference = set1.symmetricDifference(set2)

        XCTAssertEqual(symmetricDifference, [201, 204, 400, 404])
    }

    func testFormUnion() {
        var set1 = StatusCodeSet([200, 201, 202])
        let set2 = StatusCodeSet([201, 203])

        set1.formUnion(set2)

        XCTAssertEqual(set1, [200, 201, 202, 203])
    }

    func testFormIntersection() {
        var set1 = StatusCodeSet([200, 201, 202])
        let set2 = StatusCodeSet([201, 203])

        set1.formIntersection(set2)

        XCTAssertEqual(set1, [201])
    }

    func testFormSymmetricDifference() {
        var statusCodeSet = StatusCodeSet([200, 201, 202, 203])
        let other = StatusCodeSet([201, 202, 204, 205])

        statusCodeSet.formSymmetricDifference(other)

        XCTAssertEqual(statusCodeSet, [200, 203, 204, 205])
    }

    func testContains() {
        let statusCodeSet = StatusCodeSet([200, 201, 202, 203])
        XCTAssertTrue(statusCodeSet.contains(200))
        XCTAssertTrue(statusCodeSet.contains(202))
        XCTAssertFalse(statusCodeSet.contains(204))
    }

    func testInsert() {
        var set = StatusCodeSet([.ok, .created])
        let result = set.insert(.noContent)
        XCTAssertTrue(result.inserted)
        XCTAssertEqual(result.memberAfterInsert, .noContent)
        XCTAssertTrue(set.contains(.noContent))
    }

    func testRemove() {
        var set = StatusCodeSet([.ok, .created])
        let result = set.remove(.created)
        XCTAssertEqual(result, .created)
        XCTAssertFalse(set.contains(.created))
    }

    func testUpdate() {
        var set = StatusCodeSet([.ok, .created])
        let result = set.update(with: .created)
        XCTAssertEqual(result, .created)
        XCTAssertEqual(set, [.ok, .created])
    }

    func testSuccess() {
        let success = StatusCodeSet.success
        XCTAssertTrue(success.contains(.ok))
        XCTAssertTrue(success.contains(.created))
        XCTAssertTrue(success.contains(.accepted))
        XCTAssertTrue(success.contains(.nonAuthoritativeInformation))
        XCTAssertTrue(success.contains(.noContent))
        XCTAssertTrue(success.contains(.resetContent))
        XCTAssertTrue(success.contains(.partialContent))
        XCTAssertTrue(success.contains(.multiStatus))
        XCTAssertTrue(success.contains(.alreadyReported))
        XCTAssertTrue(success.contains(.imUsed))
    }

    func testSuccessAndRedirect() {
        let successAndRedirect = StatusCodeSet.successAndRedirect
        XCTAssertTrue(successAndRedirect.contains(.ok))
        XCTAssertTrue(successAndRedirect.contains(.created))
        XCTAssertTrue(successAndRedirect.contains(.accepted))
        XCTAssertTrue(successAndRedirect.contains(.nonAuthoritativeInformation))
        XCTAssertTrue(successAndRedirect.contains(.noContent))
        XCTAssertTrue(successAndRedirect.contains(.resetContent))
        XCTAssertTrue(successAndRedirect.contains(.partialContent))
        XCTAssertTrue(successAndRedirect.contains(.multiStatus))
        XCTAssertTrue(successAndRedirect.contains(.alreadyReported))
        XCTAssertTrue(successAndRedirect.contains(.imUsed))
        XCTAssertTrue(successAndRedirect.contains(.multipleChoices))
        XCTAssertTrue(successAndRedirect.contains(.movedPermanently))
        XCTAssertTrue(successAndRedirect.contains(.found))
        XCTAssertTrue(successAndRedirect.contains(.seeOther))
        XCTAssertTrue(successAndRedirect.contains(.notModified))
        XCTAssertTrue(successAndRedirect.contains(.useProxy))
        XCTAssertTrue(successAndRedirect.contains(.temporaryRedirect))
        XCTAssertTrue(successAndRedirect.contains(.permanentRedirect))
    }

}
