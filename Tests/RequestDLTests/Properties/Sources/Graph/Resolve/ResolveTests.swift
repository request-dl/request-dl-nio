/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

@RequestActor
class ResolveTests: XCTestCase {

    func testDebug_whenContainsOneHierarchy_shouldBeValid() async throws {
        // Given
        let property = Group {
            BaseURL("apple.com")
            Path("api")
            Path("v2")

            Headers.Accept(.json)
            Headers.ContentType(.json)

            Timeout(60)

            Session()
                .decompressionLimit(.ratio(500))
        }

        // When
        let debugDescription = try await Resolve(property).description()

        // Then
        XCTAssertEqual(debugDescription, Self.oneHierarchyOutput)
    }

    func testDebug_whenContainsTwoHierarchy_shouldBeValid() async throws {
        // Given
        let property = Group {
            BaseURL("apple.com")
            Path("api")
            Path("v2")

            HeaderGroup {
                Headers.Accept(.json)
                Headers.ContentType(.json)

                Timeout(60) // should be eliminated
            }

            QueryGroup {
                Query("some question", forKey: "q")
            }
        }

        // When
        let debugDescription = try await Resolve(property).description()

        // Then
        XCTAssertEqual(debugDescription, Self.twoHierarchyOutput)
    }

    func testDebug_whenContainsSecureConnection_shouldBeValid() async throws {
        // Given
        let property = Group {
            BaseURL("apple.com")

            SecureConnection {
                RequestDL.Certificates {
                    Certificate([0, 1, 2])
                }

                Trusts {
                    Certificate([6, 7, 8])
                    Certificate([8, 9, 10])
                }

                AdditionalTrusts {
                    Certificate([2, 3, 4])
                    Certificate([4, 5, 6])
                }
            }

            PrivateKey([0, 2])
        }

        // When
        let debugDescription = try await Resolve(property).description()

        // Then
        XCTAssertEqual(debugDescription, Self.secureConnectionOutput)
    }
}

extension ResolveTests {

    static var oneHierarchyOutput: String {
        """
        Resolve {
            ChildrenNode {
                LeafNode<Node> {
                    property = Node {
                        baseURL = https://apple.com
                    }
                },
                LeafNode<Node> {
                    property = Node {
                        path = api
                    }
                },
                LeafNode<Node> {
                    property = Node {
                        path = v2
                    }
                },
                LeafNode<Node> {
                    property = Node {
                        key = Accept,
                        value = application/json
                    }
                },
                LeafNode<Node> {
                    property = Node {
                        key = Content-Type,
                        value = application/json
                    }
                },
                LeafNode<Node> {
                    property = Node {
                        timeout = UnitTime {
                            nanoseconds = 60
                        },
                        source = Source {
                            rawValue = 3
                        }
                    }
                },
                LeafNode<Node> {
                    property = Node {
                        configuration = Configuration {
                            secureConnection = nil,
                            redirectConfiguration = nil,
                            timeout = Timeout {
                                connect = nil,
                                read = nil
                            },
                            connectionPool = ConnectionPool {
                                idleTimeout = TimeAmount {
                                    nanoseconds = 60000000000
                                },
                                concurrentHTTP1ConnectionsPerHostSoftLimit = 8,
                                retryConnectionEstablishment = true
                            },
                            proxy = nil,
                            ignoreUncleanSSLShutdown = false,
                            decompression = Decompression.enabled(
                                DecompressionLimit {
                                    limit = Limit.ratio(500)
                                }
                            ),
                            readingMode = ReadingMode.length(1024),
                            updatingKeyPaths = Optional<(inout Configuration) -> ()> {
                                some = (Function)
                            }
                        },
                        provider = SharedSessionProvider()
                    }
                }
            }
        }
        """
    }

    static var twoHierarchyOutput: String {
        """
        Resolve {
            ChildrenNode {
                LeafNode<Node> {
                    property = Node {
                        baseURL = https://apple.com
                    }
                },
                LeafNode<Node> {
                    property = Node {
                        path = api
                    }
                },
                LeafNode<Node> {
                    property = Node {
                        path = v2
                    }
                },
                LeafNode<Node> {
                    property = Node {
                        nodes = [
                            LeafNode<Node> {
                                property = Node {
                                    key = Accept,
                                    value = application/json
                                }
                            },
                            LeafNode<Node> {
                                property = Node {
                                    key = Content-Type,
                                    value = application/json
                                }
                            }
                        ]
                    }
                },
                LeafNode<Node> {
                    property = Node {
                        leafs = [
                            LeafNode<Node> {
                                property = Node {
                                    key = q,
                                    value = some question
                                }
                            }
                        ]
                    }
                }
            }
        }
        """
    }

    static var secureConnectionOutput: String {
        """
        Resolve {
            ChildrenNode {
                LeafNode<Node> {
                    property = Node {
                        baseURL = https://apple.com
                    }
                },
                LeafNode<Node> {
                    property = Node {
                        secureConnection = SecureConnection {
                            context = .client,
                            certificateChain = nil,
                            certificateVerification = nil,
                            trustRoots = nil,
                            additionalTrustRoots = nil,
                            privateKey = nil,
                            signingSignatureAlgorithms = nil,
                            verifySignatureAlgorithms = nil,
                            sendCANameList = nil,
                            renegotiationSupport = nil,
                            shutdownTimeout = nil,
                            pskHint = nil,
                            applicationProtocols = nil,
                            keyLogger = nil,
                            pskClientIdentityResolver = nil,
                            pskServerIdentityResolver = nil,
                            minimumTLSVersion = nil,
                            maximumTLSVersion = nil,
                            cipherSuites = nil,
                            cipherSuiteValues = nil
                        },
                        nodes = [
                            LeafNode<SecureConnectionNode> {
                                property = SecureConnectionNode {
                                    source = Source.node(
                                        Node {
                                            source = Source.nodes(
                                                [
                                                    LeafNode<SecureConnectionNode> {
                                                        property = SecureConnectionNode {
                                                            source = Source.collectorNode(
                                                                CertificateNode {
                                                                    source = Source.bytes([0, 1, 2]),
                                                                    property = .chain,
                                                                    format = .pem
                                                                }
                                                            )
                                                        }
                                                    }
                                                ]
                                            )
                                        }
                                    )
                                }
                            },
                            LeafNode<SecureConnectionNode> {
                                property = SecureConnectionNode {
                                    source = Source.node(
                                        Node {
                                            source = Source.nodes(
                                                [
                                                    LeafNode<SecureConnectionNode> {
                                                        property = SecureConnectionNode {
                                                            source = Source.collectorNode(
                                                                CertificateNode {
                                                                    source = Source.bytes([6, 7, 8]),
                                                                    property = .trust,
                                                                    format = .pem
                                                                }
                                                            )
                                                        }
                                                    },
                                                    LeafNode<SecureConnectionNode> {
                                                        property = SecureConnectionNode {
                                                            source = Source.collectorNode(
                                                                CertificateNode {
                                                                    source = Source.bytes([8, 9, 10]),
                                                                    property = .trust,
                                                                    format = .pem
                                                                }
                                                            )
                                                        }
                                                    }
                                                ]
                                            )
                                        }
                                    )
                                }
                            },
                            LeafNode<SecureConnectionNode> {
                                property = SecureConnectionNode {
                                    source = Source.node(
                                        Node {
                                            source = Source.nodes(
                                                [
                                                    LeafNode<SecureConnectionNode> {
                                                        property = SecureConnectionNode {
                                                            source = Source.collectorNode(
                                                                CertificateNode {
                                                                    source = Source.bytes([2, 3, 4]),
                                                                    property = .additionalTrust,
                                                                    format = .pem
                                                                }
                                                            )
                                                        }
                                                    },
                                                    LeafNode<SecureConnectionNode> {
                                                        property = SecureConnectionNode {
                                                            source = Source.collectorNode(
                                                                CertificateNode {
                                                                    source = Source.bytes([4, 5, 6]),
                                                                    property = .additionalTrust,
                                                                    format = .pem
                                                                }
                                                            )
                                                        }
                                                    }
                                                ]
                                            )
                                        }
                                    )
                                }
                            }
                        ]
                    }
                },
                LeafNode<SecureConnectionNode> {
                    property = SecureConnectionNode {
                        source = Source.node(
                            Node {
                                source = Source.privateKey(
                                    PrivateKey {
                                        source = Source.bytes([0, 2]),
                                        format = .pem,
                                        password = nil
                                    }
                                )
                            }
                        )
                    }
                }
            }
        }
        """
    }
}
