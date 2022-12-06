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

        if #available(iOS 16, macOS 13, watchOS 9, tvOS 16, *) {
            XCTAssertFalse(configuration.requiresDNSSECValidation)
        }

        XCTAssertFalse(configuration.waitsForConnectivity)
        XCTAssertFalse(configuration.isDiscretionary)
        XCTAssertNil(configuration.sharedContainerIdentifier)
        XCTAssertFalse(configuration.sessionSendsLaunchEvents)
        XCTAssertNil(configuration.connectionProxyDictionary)
        XCTAssertEqual(configuration.tlsMinimumSupportedProtocolVersion, .TLSv10)
        XCTAssertEqual(configuration.tlsMaximumSupportedProtocolVersion, .TLSv13)
        XCTAssertFalse(configuration.httpShouldUsePipelining)
        XCTAssertTrue(configuration.httpShouldSetCookies)
        XCTAssertEqual(configuration.httpCookieAcceptPolicy, .onlyFromMainDocumentDomain)
        XCTAssertEqual(configuration.httpMaximumConnectionsPerHost, 6)
        XCTAssertNotNil(configuration.httpCookieStorage)
        XCTAssertNotNil(configuration.urlCredentialStorage)
        XCTAssertFalse(configuration.shouldUseExtendedBackgroundIdleMode)
    }
}
