//
//  SessionTests.swift
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

import XCTest
@testable import RequestDL

final class SessionTests: XCTestCase {

    func testConfigurationBaseType() async {
        let sut1 = Test(Session(.default))
        let sut2 = Test(Session(.ephemeral))
        let sut3 = Test(Session(.background("123"), queue: .main))

        let (session1, _) = await resolve(sut1)
        let (session2, _) = await resolve(sut2)
        let (session3, _) = await resolve(sut3)

        XCTAssertEqual(session1.configuration, .default)
        XCTAssertEqual(session2.configuration.urlCache?.diskCapacity, .zero)
        XCTAssertEqual(session3.configuration.identifier, "123")
        XCTAssertEqual(session3.delegateQueue, .main)
    }

    func testEmptyConfiguration() async {
        let sut = Test(Session(.default))

        let (session, _) = await resolve(sut)
        let configuration = session.configuration

        XCTAssertEqual(configuration.networkServiceType, .default)
        XCTAssertTrue(configuration.allowsCellularAccess)
        XCTAssertTrue(configuration.allowsExpensiveNetworkAccess)
        XCTAssertTrue(configuration.allowsConstrainedNetworkAccess)

        #if swift(>=5.7.2)
        if #available(iOS 16, macOS 13, watchOS 9, tvOS 16, *) {
            XCTAssertFalse(configuration.requiresDNSSECValidation)
        }
        #endif

        XCTAssertFalse(configuration.waitsForConnectivity)
        XCTAssertFalse(configuration.isDiscretionary)
        XCTAssertNil(configuration.sharedContainerIdentifier)
        XCTAssertFalse(configuration.sessionSendsLaunchEvents)
        XCTAssertNil(configuration.connectionProxyDictionary)
        XCTAssertFalse(configuration.httpShouldUsePipelining)
        XCTAssertTrue(configuration.httpShouldSetCookies)
        XCTAssertEqual(configuration.httpCookieAcceptPolicy, .onlyFromMainDocumentDomain)
        XCTAssertEqual(configuration.httpMaximumConnectionsPerHost, 6)
        XCTAssertNotNil(configuration.httpCookieStorage)
        XCTAssertNotNil(configuration.urlCredentialStorage)
        XCTAssertFalse(configuration.shouldUseExtendedBackgroundIdleMode)
    }

    func testNetworkService() async {
        for type in [.video, .background, .callSignaling] as [URLRequest.NetworkServiceType] {
            let sut = Test {
                Session(.default)
                    .networkService(type)
            }

            let (session, _) = await resolve(sut)
            let configuration = session.configuration

            XCTAssertEqual(configuration.networkServiceType, type)
        }
    }

    func testCellularAccess() async {
        let sut1 = Test {
            Session(.default)
                .cellularAccessDisabled(false)
        }

        let sut2 = Test {
            Session(.default)
                .cellularAccessDisabled(true)
        }

        let sut3 = Test {
            Session(.default)
                .cellularAccessDisabled(true)
                .cellularAccessDisabled(false)
        }

        let (session1, _) = await resolve(sut1)
        let (session2, _) = await resolve(sut2)
        let (session3, _) = await resolve(sut3)

        let configuration1 = session1.configuration
        let configuration2 = session2.configuration
        let configuration3 = session3.configuration

        XCTAssertTrue(configuration1.allowsCellularAccess)
        XCTAssertFalse(configuration2.allowsCellularAccess)
        XCTAssertTrue(configuration3.allowsCellularAccess)
    }

    func testExpensiveNetworkAccess() async {
        let sut1 = Test {
            Session(.default)
                .expensiveNetworkDisabled(false)
        }

        let sut2 = Test {
            Session(.default)
                .expensiveNetworkDisabled(true)
        }

        let sut3 = Test {
            Session(.default)
                .expensiveNetworkDisabled(true)
                .expensiveNetworkDisabled(false)
        }

        let (session1, _) = await resolve(sut1)
        let (session2, _) = await resolve(sut2)
        let (session3, _) = await resolve(sut3)

        let configuration1 = session1.configuration
        let configuration2 = session2.configuration
        let configuration3 = session3.configuration

        XCTAssertTrue(configuration1.allowsExpensiveNetworkAccess)
        XCTAssertFalse(configuration2.allowsExpensiveNetworkAccess)
        XCTAssertTrue(configuration3.allowsExpensiveNetworkAccess)
    }

    func testConstrainedNetworkAccess() async {
        let sut1 = Test {
            Session(.default)
                .constrainedNetworkDisabled(false)
        }

        let sut2 = Test {
            Session(.default)
                .constrainedNetworkDisabled(true)
        }

        let sut3 = Test {
            Session(.default)
                .constrainedNetworkDisabled(true)
                .constrainedNetworkDisabled(false)
        }

        let (session1, _) = await resolve(sut1)
        let (session2, _) = await resolve(sut2)
        let (session3, _) = await resolve(sut3)

        let configuration1 = session1.configuration
        let configuration2 = session2.configuration
        let configuration3 = session3.configuration

        XCTAssertTrue(configuration1.allowsConstrainedNetworkAccess)
        XCTAssertFalse(configuration2.allowsConstrainedNetworkAccess)
        XCTAssertTrue(configuration3.allowsConstrainedNetworkAccess)
    }

    func testWaitsForConnectivity() async {
        let sut1 = Test {
            Session(.default)
                .waitsForConnectivity(true)
        }

        let sut2 = Test {
            Session(.default)
                .waitsForConnectivity(false)
        }

        let sut3 = Test {
            Session(.default)
                .waitsForConnectivity(false)
                .waitsForConnectivity(true)
        }

        let (session1, _) = await resolve(sut1)
        let (session2, _) = await resolve(sut2)
        let (session3, _) = await resolve(sut3)

        let configuration1 = session1.configuration
        let configuration2 = session2.configuration
        let configuration3 = session3.configuration

        XCTAssertTrue(configuration1.waitsForConnectivity)
        XCTAssertFalse(configuration2.waitsForConnectivity)
        XCTAssertTrue(configuration3.waitsForConnectivity)
    }

    func testDiscretionary() async {
        let sut1 = Test {
            Session(.default)
                .discretionary(true)
        }

        let sut2 = Test {
            Session(.default)
                .discretionary(false)
        }

        let sut3 = Test {
            Session(.default)
                .discretionary(false)
                .discretionary(true)
        }

        let (session1, _) = await resolve(sut1)
        let (session2, _) = await resolve(sut2)
        let (session3, _) = await resolve(sut3)

        let configuration1 = session1.configuration
        let configuration2 = session2.configuration
        let configuration3 = session3.configuration

        XCTAssertTrue(configuration1.isDiscretionary)
        XCTAssertFalse(configuration2.isDiscretionary)
        XCTAssertTrue(configuration3.isDiscretionary)
    }

    func testSharedContainerIdentifier() async {
        let sut1 = Test {
            Session(.default)
                .sharedContainerIdentifier("test1")
        }

        let sut2 = Test {
            Session(.default)
                .sharedContainerIdentifier("test2")
        }

        let sut3 = Test {
            Session(.default)
                .sharedContainerIdentifier("test3")
                .sharedContainerIdentifier("test4")
        }

        let (session1, _) = await resolve(sut1)
        let (session2, _) = await resolve(sut2)
        let (session3, _) = await resolve(sut3)

        let configuration1 = session1.configuration
        let configuration2 = session2.configuration
        let configuration3 = session3.configuration

        XCTAssertEqual(configuration1.sharedContainerIdentifier, "test1")
        XCTAssertEqual(configuration2.sharedContainerIdentifier, "test2")
        XCTAssertEqual(configuration3.sharedContainerIdentifier, "test4")
    }

    func testLaunchEvents() async {
        let sut1 = Test {
            Session(.default)
                .sendsLaunchEvents(true)
        }

        let sut2 = Test {
            Session(.default)
                .sendsLaunchEvents(false)
        }

        let sut3 = Test {
            Session(.default)
                .sendsLaunchEvents(true)
                .sendsLaunchEvents(false)
        }

        let (session1, _) = await resolve(sut1)
        let (session2, _) = await resolve(sut2)
        let (session3, _) = await resolve(sut3)

        let configuration1 = session1.configuration
        let configuration2 = session2.configuration
        let configuration3 = session3.configuration

        XCTAssertTrue(configuration1.sessionSendsLaunchEvents)
        XCTAssertFalse(configuration2.sessionSendsLaunchEvents)
        XCTAssertFalse(configuration3.sessionSendsLaunchEvents)
    }

    func testConnectionProxyDictionary() async {
        let value1 = ["key1": 1]
        let value2 = ["key2": 2]
        let value3 = ["key4": 4, "key5": 5]

        let sut1 = Test {
            Session(.default)
                .connectionProxyDictionary(value1)
        }

        let sut2 = Test {
            Session(.default)
                .connectionProxyDictionary(value2)
        }

        let sut3 = Test {
            Session(.default)
                .connectionProxyDictionary(["key3": 3])
                .connectionProxyDictionary(value3)
        }

        let (session1, _) = await resolve(sut1)
        let (session2, _) = await resolve(sut2)
        let (session3, _) = await resolve(sut3)

        let configuration1 = session1.configuration
        let configuration2 = session2.configuration
        let configuration3 = session3.configuration

        XCTAssertEqual(configuration1.connectionProxyDictionary as? [String: Int], value1)
        XCTAssertEqual(configuration2.connectionProxyDictionary as? [String: Int], value2)
        XCTAssertEqual(configuration3.connectionProxyDictionary as? [String: Int], value3)
    }
}
