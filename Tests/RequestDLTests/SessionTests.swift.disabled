/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

// swiftlint:disable type_body_length function_body_length file_length
final class SessionTests: XCTestCase {

    func testDefaultConfiguration() async throws {
        // Given
        let property = Session(.default)
        let configuration = URLSessionConfiguration.default

        // When
        let (session, _) = try await resolve(TestProperty { property })

        // Then
        XCTAssertEqual(
            session.configuration.networkServiceType,
            configuration.networkServiceType
        )

        XCTAssertEqual(
            session.configuration.allowsCellularAccess,
            configuration.allowsCellularAccess
        )

        XCTAssertEqual(
            session.configuration.allowsExpensiveNetworkAccess,
            configuration.allowsExpensiveNetworkAccess
        )

        XCTAssertEqual(
            session.configuration.allowsConstrainedNetworkAccess,
            configuration.allowsConstrainedNetworkAccess
        )

        #if swift(>=5.7.2)
        if #available(iOS 16, macOS 13, watchOS 9, tvOS 16, *) {
            XCTAssertEqual(
                session.configuration.requiresDNSSECValidation,
                configuration.requiresDNSSECValidation
            )
        }
        #endif

        XCTAssertEqual(
            session.configuration.waitsForConnectivity,
            configuration.waitsForConnectivity
        )

        XCTAssertEqual(
            session.configuration.isDiscretionary,
            configuration.isDiscretionary
        )

        XCTAssertEqual(
            session.configuration.sharedContainerIdentifier,
            configuration.sharedContainerIdentifier
        )

        XCTAssertEqual(
            session.configuration.sessionSendsLaunchEvents,
            configuration.sessionSendsLaunchEvents
        )

        XCTAssertEqual(
            session.configuration.connectionProxyDictionary?.mapValues { "\($0)" },
            configuration.connectionProxyDictionary?.mapValues { "\($0)" }
        )

        XCTAssertEqual(
            session.configuration.tlsMinimumSupportedProtocolVersion,
            configuration.tlsMinimumSupportedProtocolVersion
        )

        XCTAssertEqual(
            session.configuration.tlsMaximumSupportedProtocolVersion,
            configuration.tlsMaximumSupportedProtocolVersion
        )

        XCTAssertEqual(
            session.configuration.httpShouldUsePipelining,
            configuration.httpShouldUsePipelining
        )

        XCTAssertEqual(
            session.configuration.httpShouldSetCookies,
            configuration.httpShouldSetCookies
        )

        XCTAssertEqual(
            session.configuration.httpCookieAcceptPolicy,
            configuration.httpCookieAcceptPolicy
        )

        XCTAssertEqual(
            session.configuration.httpMaximumConnectionsPerHost,
            configuration.httpMaximumConnectionsPerHost
        )

        XCTAssertEqual(
            session.configuration.httpCookieStorage?.cookieAcceptPolicy,
            configuration.httpCookieStorage?.cookieAcceptPolicy
        )

        XCTAssertEqual(
            session.configuration.httpCookieStorage?.cookies?.count,
            configuration.httpCookieStorage?.cookies?.count
        )

        XCTAssertEqual(
            session.configuration.urlCredentialStorage?.allCredentials,
            configuration.urlCredentialStorage?.allCredentials
        )

        XCTAssertEqual(
            session.configuration.shouldUseExtendedBackgroundIdleMode,
            configuration.shouldUseExtendedBackgroundIdleMode
        )

        XCTAssertEqual(
            session.configuration.identifier,
            configuration.identifier
        )

        XCTAssertEqual(
            session.configuration.requestCachePolicy,
            configuration.requestCachePolicy
        )
    }

    func testEphemeralConfiguration() async throws {
        // Given
        let property = Session(.ephemeral)
        let configuration = URLSessionConfiguration.ephemeral

        // When
        let (session, _) = try await resolve(TestProperty { property })

        // Then
        XCTAssertEqual(
            session.configuration.networkServiceType,
            configuration.networkServiceType
        )

        XCTAssertEqual(
            session.configuration.allowsCellularAccess,
            configuration.allowsCellularAccess
        )

        XCTAssertEqual(
            session.configuration.allowsExpensiveNetworkAccess,
            configuration.allowsExpensiveNetworkAccess
        )

        XCTAssertEqual(
            session.configuration.allowsConstrainedNetworkAccess,
            configuration.allowsConstrainedNetworkAccess
        )

        #if swift(>=5.7.2)
        if #available(iOS 16, macOS 13, watchOS 9, tvOS 16, *) {
            XCTAssertEqual(
                session.configuration.requiresDNSSECValidation,
                configuration.requiresDNSSECValidation
            )
        }
        #endif

        XCTAssertEqual(
            session.configuration.waitsForConnectivity,
            configuration.waitsForConnectivity
        )

        XCTAssertEqual(
            session.configuration.isDiscretionary,
            configuration.isDiscretionary
        )

        XCTAssertEqual(
            session.configuration.sharedContainerIdentifier,
            configuration.sharedContainerIdentifier
        )

        XCTAssertEqual(
            session.configuration.sessionSendsLaunchEvents,
            configuration.sessionSendsLaunchEvents
        )

        XCTAssertEqual(
            session.configuration.connectionProxyDictionary?.mapValues { "\($0)" },
            configuration.connectionProxyDictionary?.mapValues { "\($0)" }
        )

        XCTAssertEqual(
            session.configuration.tlsMinimumSupportedProtocolVersion,
            configuration.tlsMinimumSupportedProtocolVersion
        )

        XCTAssertEqual(
            session.configuration.tlsMaximumSupportedProtocolVersion,
            configuration.tlsMaximumSupportedProtocolVersion
        )

        XCTAssertEqual(
            session.configuration.httpShouldUsePipelining,
            configuration.httpShouldUsePipelining
        )

        XCTAssertEqual(
            session.configuration.httpShouldSetCookies,
            configuration.httpShouldSetCookies
        )

        XCTAssertEqual(
            session.configuration.httpCookieAcceptPolicy,
            configuration.httpCookieAcceptPolicy
        )

        XCTAssertEqual(
            session.configuration.httpMaximumConnectionsPerHost,
            configuration.httpMaximumConnectionsPerHost
        )

        XCTAssertEqual(
            session.configuration.httpCookieStorage?.cookieAcceptPolicy,
            configuration.httpCookieStorage?.cookieAcceptPolicy
        )

        XCTAssertEqual(
            session.configuration.httpCookieStorage?.cookies?.count,
            configuration.httpCookieStorage?.cookies?.count
        )

        XCTAssertEqual(
            session.configuration.urlCredentialStorage?.allCredentials,
            configuration.urlCredentialStorage?.allCredentials
        )

        XCTAssertEqual(
            session.configuration.shouldUseExtendedBackgroundIdleMode,
            configuration.shouldUseExtendedBackgroundIdleMode
        )

        XCTAssertEqual(
            session.configuration.identifier,
            configuration.identifier
        )

        XCTAssertEqual(
            session.configuration.requestCachePolicy,
            configuration.requestCachePolicy
        )
    }

    func testBackgroundConfiguration() async throws {
        // Given
        let backgroundID = "id"
        let property = Session(.background(backgroundID))
        let configuration = URLSessionConfiguration.background(withIdentifier: backgroundID)

        // When
        let (session, _) = try await resolve(TestProperty { property })

        // Then
        XCTAssertEqual(
            session.configuration.networkServiceType,
            configuration.networkServiceType
        )

        XCTAssertEqual(
            session.configuration.allowsCellularAccess,
            configuration.allowsCellularAccess
        )

        XCTAssertEqual(
            session.configuration.allowsExpensiveNetworkAccess,
            configuration.allowsExpensiveNetworkAccess
        )

        XCTAssertEqual(
            session.configuration.allowsConstrainedNetworkAccess,
            configuration.allowsConstrainedNetworkAccess
        )

        #if swift(>=5.7.2)
        if #available(iOS 16, macOS 13, watchOS 9, tvOS 16, *) {
            XCTAssertEqual(
                session.configuration.requiresDNSSECValidation,
                configuration.requiresDNSSECValidation
            )
        }
        #endif

        XCTAssertEqual(
            session.configuration.waitsForConnectivity,
            configuration.waitsForConnectivity
        )

        XCTAssertEqual(
            session.configuration.isDiscretionary,
            configuration.isDiscretionary
        )

        XCTAssertEqual(
            session.configuration.sharedContainerIdentifier,
            configuration.sharedContainerIdentifier
        )

        XCTAssertEqual(
            session.configuration.sessionSendsLaunchEvents,
            configuration.sessionSendsLaunchEvents
        )

        XCTAssertEqual(
            session.configuration.connectionProxyDictionary?.mapValues { "\($0)" },
            configuration.connectionProxyDictionary?.mapValues { "\($0)" }
        )

        XCTAssertEqual(
            session.configuration.tlsMinimumSupportedProtocolVersion,
            configuration.tlsMinimumSupportedProtocolVersion
        )

        XCTAssertEqual(
            session.configuration.tlsMaximumSupportedProtocolVersion,
            configuration.tlsMaximumSupportedProtocolVersion
        )

        XCTAssertEqual(
            session.configuration.httpShouldUsePipelining,
            configuration.httpShouldUsePipelining
        )

        XCTAssertEqual(
            session.configuration.httpShouldSetCookies,
            configuration.httpShouldSetCookies
        )

        XCTAssertEqual(
            session.configuration.httpCookieAcceptPolicy,
            configuration.httpCookieAcceptPolicy
        )

        XCTAssertEqual(
            session.configuration.httpMaximumConnectionsPerHost,
            configuration.httpMaximumConnectionsPerHost
        )

        XCTAssertEqual(
            session.configuration.httpCookieStorage,
            configuration.httpCookieStorage
        )

        XCTAssertEqual(
            session.configuration.urlCredentialStorage?.allCredentials,
            configuration.urlCredentialStorage?.allCredentials
        )

        XCTAssertEqual(
            session.configuration.shouldUseExtendedBackgroundIdleMode,
            configuration.shouldUseExtendedBackgroundIdleMode
        )

        XCTAssertEqual(
            session.configuration.identifier,
            configuration.identifier
        )

        XCTAssertEqual(
            session.configuration.requestCachePolicy,
            configuration.requestCachePolicy
        )

        XCTAssertEqual(
            session.configuration.urlCache,
            configuration.urlCache
        )
    }

    func testNetworkService() async throws {
        // Given
        let networkService: URLRequest.NetworkServiceType = .video

        // When
        let (session, _) = try await resolve(
            TestProperty {
                Session(.default)
                    .networkService(networkService)
            }
        )

        // Then
        XCTAssertEqual(
            session.configuration.networkServiceType,
            networkService
        )
    }

    func testCellularAccessDisabled() async throws {
        // Given
        let cellularAccessDisabled = true

        // When
        let (session, _) = try await resolve(
            TestProperty {
                Session(.default)
                    .cellularAccessDisabled(cellularAccessDisabled)
            }
        )

        // Then
        XCTAssertEqual(
            session.configuration.allowsCellularAccess,
            !cellularAccessDisabled
        )
    }

    func testExpensiveNetworkDisabled() async throws {
        // Given
        let expensiveNetworkDisabled = true

        // When
        let (session, _) = try await resolve(
            TestProperty {
                Session(.default)
                    .expensiveNetworkDisabled(expensiveNetworkDisabled)
            }
        )

        // Then
        XCTAssertEqual(
            session.configuration.allowsExpensiveNetworkAccess,
            !expensiveNetworkDisabled
        )
    }

    func testConstrainedNetworkDisabled() async throws {
        // Given
        let constrainedNetworkDisabled = true

        // When
        let (session, _) = try await resolve(
            TestProperty {
                Session(.default)
                    .constrainedNetworkDisabled(constrainedNetworkDisabled)
            }
        )

        // Then
        XCTAssertEqual(
            session.configuration.allowsConstrainedNetworkAccess,
            !constrainedNetworkDisabled
        )
    }

    func testWaitsForConnectivity() async throws {
        // Given
        let waitsForConnectivity = true

        // When
        let (session, _) = try await resolve(
            TestProperty {
                Session(.default)
                    .waitsForConnectivity(waitsForConnectivity)
            }
        )

        // Then
        XCTAssertEqual(
            session.configuration.waitsForConnectivity,
            waitsForConnectivity
        )
    }

    func testDiscretionary() async throws {
        // Given
        let discretionary = true

        // When
        let (session, _) = try await resolve(
            TestProperty {
                Session(.default)
                    .discretionary(discretionary)
            }
        )

        // Then
        XCTAssertEqual(
            session.configuration.isDiscretionary,
            discretionary
        )
    }

    func testSharedContainerIdentifier() async throws {
        // Given
        let sharedContainerIdentifier = "unit.test"

        // When
        let (session, _) = try await resolve(
            TestProperty {
                Session(.default)
                    .sharedContainerIdentifier(sharedContainerIdentifier)
            }
        )

        // Then
        XCTAssertEqual(
            session.configuration.sharedContainerIdentifier,
            sharedContainerIdentifier
        )
    }

    func testSendsLaunchEvents() async throws {
        // Given
        let sendsLaunchEvents = true

        // When
        let (session, _) = try await resolve(
            TestProperty {
                Session(.default)
                    .sendsLaunchEvents(sendsLaunchEvents)
            }
        )

        // Then
        XCTAssertEqual(
            session.configuration.sessionSendsLaunchEvents,
            sendsLaunchEvents
        )
    }

    func testConnectionProxyDictionary() async throws {
        // Given
        let connectionProxyDictionary = [AnyHashable: Any]()

        // When
        let (session, _) = try await resolve(
            TestProperty {
                Session(.default)
                    .connectionProxyDictionary(connectionProxyDictionary)
            }
        )

        // Then
        XCTAssertEqual(
            session.configuration.connectionProxyDictionary?.mapValues { "\($0)" },
            connectionProxyDictionary.mapValues { "\($0)" }
        )
    }

    func testProtocolSupported() async throws {
        // Given
        let tlsProtocolSupportedMin = tls_protocol_version_t.TLSv11
        let tlsProtocolSupportedMax = tls_protocol_version_t.TLSv11

        // When
        let (session, _) = try await resolve(
            TestProperty {
                Session(.default)
                    .tlsProtocolSupported(
                        minimum: tlsProtocolSupportedMin,
                        maximum: tlsProtocolSupportedMax
                    )
            }
        )

        // Then
        XCTAssertEqual(
            session.configuration.tlsMinimumSupportedProtocolVersion,
            tlsProtocolSupportedMin
        )

        XCTAssertEqual(
            session.configuration.tlsMaximumSupportedProtocolVersion,
            tlsProtocolSupportedMax
        )
    }

    func testPipeliningDisabled() async throws {
        // Given
        let pipeliningDisabled = false

        // When
        let (session, _) = try await resolve(
            TestProperty {
                Session(.default)
                    .pipeliningDisabled(pipeliningDisabled)
            }
        )

        // Then
        XCTAssertEqual(
            session.configuration.httpShouldUsePipelining,
            !pipeliningDisabled
        )
    }

    func testSetCookiesDisabled() async throws {
        // Given
        let setCookiesDisabled = true

        // When
        let (session, _) = try await resolve(
            TestProperty {
                Session(.default)
                    .setCookiesDisabled(setCookiesDisabled)
            }
        )

        // Then
        XCTAssertEqual(
            session.configuration.httpShouldSetCookies,
            !setCookiesDisabled
        )
    }

    func testCookieAcceptPolicy() async throws {
        // Given
        let cookieAcceptPolicy: HTTPCookie.AcceptPolicy = .never

        // When
        let (session, _) = try await resolve(
            TestProperty {
                Session(.default)
                    .cookieAcceptPolicy(cookieAcceptPolicy)
            }
        )

        // Then
        XCTAssertEqual(
            session.configuration.httpCookieAcceptPolicy,
            cookieAcceptPolicy
        )
    }

    func testCookieStorage() async throws {
        // Given
        let cookieStorage = HTTPCookieStorage()

        // When
        let (session, _) = try await resolve(
            TestProperty {
                Session(.default)
                    .cookieStorage(cookieStorage)
            }
        )

        // Then
        XCTAssertEqual(
            session.configuration.httpCookieStorage,
            cookieStorage
        )
    }

    func testMaximumConnectionsPerHost() async throws {
        // Given
        let maximumConnectionsPerHost = 5

        // When
        let (session, _) = try await resolve(
            TestProperty {
                Session(.default)
                    .maximumConnectionsPerHost(maximumConnectionsPerHost)
            }
        )

        // Then
        XCTAssertEqual(
            session.configuration.httpMaximumConnectionsPerHost,
            maximumConnectionsPerHost
        )
    }

    func testExtendedBackgroundIdleModeDisabled() async throws {
        // Given
        let extendedBackgroundIdleModeDisabled = false

        // When
        let (session, _) = try await resolve(
            TestProperty {
                Session(.default)
                    .extendedBackgroundIdleModeDisabled(extendedBackgroundIdleModeDisabled)
            }
        )

        // Then
        XCTAssertEqual(
            session.configuration.shouldUseExtendedBackgroundIdleMode,
            !extendedBackgroundIdleModeDisabled
        )
    }

    #if swift(>=5.7.2)
    @available(iOS 16, macOS 13, watchOS 9, tvOS 16, *)
    func testValidatesDNSSec() async throws {
        // Given
        let validatesDNSSec = true

        // When
        let (session, _) = try await resolve(
            TestProperty {
                Session(.default)
                    .validatesDNSSec(validatesDNSSec)
            }
        )

        // Then
        XCTAssertEqual(
            session.configuration.requiresDNSSECValidation,
            validatesDNSSec
        )
    }
    #endif

    func testCredentialStorage() async throws {
        // Given
        let credentialStorage = URLCredentialStorage()

        // When
        let (session, _) = try await resolve(
            TestProperty {
                Session(.default)
                    .credentialStorage(credentialStorage)
            }
        )

        // Then
        XCTAssertEqual(
            session.configuration.urlCredentialStorage,
            credentialStorage
        )
    }
}
