/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class HTTPHeadersTests: XCTestCase {

    func testInitWithEmptyParameters() {
        let headers = HTTPHeaders()
        XCTAssertTrue(headers.isEmpty)
        XCTAssertEqual(headers.count, 0)
        XCTAssertEqual(headers.keys, [])
    }

    func testInitWithArray() {
        let headers = HTTPHeaders([("key1", "value1"), ("key2", "value2")])
        XCTAssertFalse(headers.isEmpty)
        XCTAssertEqual(headers.count, 2)
        XCTAssertEqual(headers.keys.sorted(), ["key1", "key2"])
        XCTAssertEqual(headers.getValue(forKey: "key1"), "value1")
        XCTAssertEqual(headers.getValue(forKey: "key2"), "value2")
    }

    func testInitWithDictionary() {
        let headers = HTTPHeaders(["key1": "value1", "key2": "value2"])
        XCTAssertFalse(headers.isEmpty)
        XCTAssertEqual(headers.count, 2)
        XCTAssertEqual(headers.keys.sorted(), ["key1", "key2"])
        XCTAssertEqual(headers.getValue(forKey: "key1"), "value1")
        XCTAssertEqual(headers.getValue(forKey: "key2"), "value2")
    }

    func testSetValueForKey() {
        var headers = HTTPHeaders()
        headers.setValue("value1", forKey: "key1")
        XCTAssertFalse(headers.isEmpty)
        XCTAssertEqual(headers.count, 1)
        XCTAssertEqual(headers.keys, ["key1"])
        XCTAssertEqual(headers.getValue(forKey: "key1"), "value1")
    }
}
