/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class ResolveTests: XCTestCase {

    func testDebug_whenContainsOneHierarchy_shouldBeValid() async throws {
        // Given
        let property = PropertyGroup {
            BaseURL("apple.com")
            Path("api")
            Path("v2")

            AcceptHeader(.json)
            CacheHeader()
                .public(true)

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
        let property = PropertyGroup {
            BaseURL("apple.com")
            Path("api")
            Path("v2")

            HeaderGroup {
                AcceptHeader(.json)
                CacheHeader()
                    .public(true)

                Timeout(60) // should be eliminated
            }

            QueryGroup {
                Query(name: "q", value: "some question")
            }
        }

        // When
        let debugDescription = try await Resolve(property).description()

        // Then
        XCTAssertEqual(debugDescription, Self.twoHierarchyOutput)
    }

    func testDebug_whenContainsSecureConnection_shouldBeValid() async throws {
        // Given
        let property = PropertyGroup {
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
                LeafNode<HeaderNode> {
                    property = HeaderNode {
                        key = Accept,
                        value = application/json,
                        strategy = .adding,
                        separator = nil
                    }
                },
                LeafNode<HeaderNode> {
                    property = HeaderNode {
                        key = Cache-Control,
                        value = public,
                        strategy = .adding,
                        separator = Optional<String> {
                            some = ,
                        }
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
                        configuration = Optional<@Sendable (inout Configuration) -> ()> {
                            some = (Function)
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
                            LeafNode<HeaderNode> {
                                property = HeaderNode {
                                    key = Accept,
                                    value = application/json,
                                    strategy = .adding,
                                    separator = nil
                                }
                            },
                            LeafNode<HeaderNode> {
                                property = HeaderNode {
                                    key = Cache-Control,
                                    value = public,
                                    strategy = .adding,
                                    separator = Optional<String> {
                                        some = ,
                                    }
                                }
                            }
                        ]
                    }
                },
                LeafNode<Node> {
                    property = Node {
                        leafs = [
                            LeafNode<QueryNode> {
                                property = QueryNode {
                                    name = q,
                                    value = some question,
                                    urlEncoder = URLEncoder {
                                        lock = Lock {
                                            _lock = NIOLock {
                                                _storage = NIOConcurrencyHelpers.LockStorage<()>
                                            }
                                        },
                                        _dateEncodingStrategy = .iso8601,
                                        _keyEncodingStrategy = .literal,
                                        _dataEncodingStrategy = .base64,
                                        _boolEncodingStrategy = .literal,
                                        _optionalEncodingStrategy = .literal,
                                        _arrayEncodingStrategy = .droppingIndex,
                                        _dictionaryEncodingStrategy = .subscripted,
                                        _whitespaceEncodingStrategy = .percentEscaping
                                    }
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
                            pskIdentityResolver = nil,
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
