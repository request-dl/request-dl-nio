//
//  File.swift
//
//
//  Created by Brenno on 02/03/23.
//

import XCTest
@testable import RequestDL

final class QueryTests: XCTestCase {

    var delegate: DelegateProxy!

    override func setUp() async throws {
        delegate = .init()
    }

    override func tearDown() async throws {
        delegate = nil
    }

    func testQueries() async {
        let sut1 = Test(Query("iphone", forKey: "q"))
        let sut2 = Test(Query("https://google.com", forKey: "redirect"))
        let sut3 = Test(Query(123, forKey: "parameter"))

        let (_, request1) = await resolve(sut1)
        let (_, request2) = await resolve(sut2)
        let (_, request3) = await resolve(sut3)

        XCTAssertEqual(request1.url?.absoluteString, "https://www.apple.com/?q=iphone")
        XCTAssertEqual(request2.url?.absoluteString, "https://www.apple.com/?redirect=https://google.com")
        XCTAssertEqual(request3.url?.absoluteString, "https://www.apple.com/?parameter=123")
    }

    func testMultipleQueries() async {
        let sut1 = Test {
            Query("iphone", forKey: "q")
            Query("https://google.com", forKey: "redirect")
        }

        let (_, request1) = await resolve(sut1)

        XCTAssertEqual(request1.url?.absoluteString, "https://www.apple.com/?q=iphone&redirect=https://google.com")
    }

    func testMultipleQueriesWithPath() async {
        let sut1 = Test {
            Path("search")
            Query("iphone", forKey: "q")
            Query("https://google.com", forKey: "redirect")
            Path("example")
        }

        let (_, request1) = await resolve(sut1)

        XCTAssertEqual(request1.url?.absoluteString, """
        https://www.apple.com/search/example?q=iphone&redirect=https://google.com
        """)
    }

    func testQueryGroup() async {
        let sut1 = Test {
            QueryGroup {
                Query(1, forKey: "number")
                Query("test", forKey: "string")
                Query(1.0, forKey: "double")
            }
        }

        let (_, request1) = await resolve(sut1)

        XCTAssertEqual(request1.url?.absoluteString, "https://www.apple.com/?number=1&string=test&double=1.0")
    }
}
