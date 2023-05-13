/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

@RequestActor
class StoredObjectTests: XCTestCase {

    typealias Toolbox = StoredObjectToolbox

    func testStored_whenPath_shouldIndexBeOneAndPathZero() async throws {
        // Given
        final class Factory: Index, IndexFactory {
            static let producer = IndexProducer()

            init() {
                super.init(Self.producer)
            }
        }

        let toolbox = toolbox(Factory.self)

        // When
        let resolved1 = try await resolve(TestProperty {
            toolbox.Path()
        })

        let resolved2 = try await resolve(TestProperty {
            toolbox.Path()
        })

        // Then
        XCTAssertEqual(Factory.producer.index, 1)
        XCTAssertEqual(resolved1.request.url, resolved2.request.url)
        XCTAssertEqual(resolved1.request.url, "https://www.apple.com/0")
    }

    func testStored_whenPathDifferentPosition_shouldBeNotEqual() async throws {
        // Given
        final class Factory: Index, IndexFactory {
            static let producer = IndexProducer()

            init() {
                super.init(Self.producer)
            }
        }

        let toolbox = toolbox(Factory.self)

        // When
        let resolved1 = try await resolve(TestProperty {
            BaseURL("www.google.com")
            toolbox.Path()
        })

        let resolved2 = try await resolve(TestProperty {
            toolbox.Path()
            BaseURL("www.google.com")
        })

        // Then
        XCTAssertEqual(Factory.producer.index, 1)
        XCTAssertEqual(resolved1.request.url, resolved2.request.url)
        XCTAssertEqual(resolved1.request.url, "https://www.google.com/0")
        XCTAssertEqual(resolved2.request.url, "https://www.google.com/0")
    }

    func testStored_whenPathWithEqualNamespace() async throws {
        // Given
        final class Factory: Index, IndexFactory {
            static let producer = IndexProducer()

            init() {
                super.init(Self.producer)
            }
        }

        let toolbox = toolbox(Factory.self)

        // When
        let resolved1 = try await resolve(TestProperty {
            toolbox.Path()
                .modifier(toolbox.OneNamespaceModifier())
        })

        let resolved2 = try await resolve(TestProperty {
            toolbox.Path()
                .modifier(toolbox.OneNamespaceModifier())
        })

        // Then
        XCTAssertEqual(Factory.producer.index, 1)
        XCTAssertEqual(resolved1.request.url, resolved2.request.url)
        XCTAssertEqual(resolved1.request.url, "https://www.apple.com/0")
    }

    func testStored_whenPathWithDifferentNamespace() async throws {
        // Given
        final class Factory: Index, IndexFactory {
            static let producer = IndexProducer()

            init() {
                super.init(Self.producer)
            }
        }

        let toolbox = toolbox(Factory.self)

        // When
        let resolved1 = try await resolve(TestProperty {
            toolbox.Path()
                .modifier(toolbox.OneNamespaceModifier())
        })

        let resolved2 = try await resolve(TestProperty {
            toolbox.Path()
                .modifier(toolbox.TwoNamespaceModifier())
        })

        // Then
        XCTAssertEqual(Factory.producer.index, 2)
        XCTAssertEqual(resolved1.request.url, "https://www.apple.com/0")
        XCTAssertEqual(resolved2.request.url, "https://www.apple.com/1")
    }

    func testStored_whenPathQuery_shouldURLContainsZeroAndOnes() async throws {
        // Given
        final class Factory: Index, IndexFactory {
            static let producer = IndexProducer()

            init() {
                super.init(Self.producer)
            }
        }

        let toolbox = toolbox(Factory.self)

        // When
        let resolved1 = try await resolve(TestProperty {
            toolbox.Path()
            toolbox.Query()
        })

        let resolved2 = try await resolve(TestProperty {
            toolbox.Path()
            toolbox.Query()
        })

        // Then
        XCTAssertEqual(Factory.producer.index, 2)
        XCTAssertEqual(resolved1.request.url, resolved2.request.url)
        XCTAssertEqual(resolved1.request.url, "https://www.apple.com/0?index=1")
    }

    func testStored_whenPathQueryDifferentPosition_shouldBeNotEqual() async throws {
        // Given
        final class Factory: Index, IndexFactory {
            static let producer = IndexProducer()

            init() {
                super.init(Self.producer)
            }
        }

        let toolbox = toolbox(Factory.self)

        // When
        let resolved1 = try await resolve(TestProperty {
            toolbox.Path()
            toolbox.Query()
        })

        let resolved2 = try await resolve(TestProperty {
            toolbox.Query()
            toolbox.Path()
        })

        // Then
        XCTAssertEqual(Factory.producer.index, 4)
        XCTAssertNotEqual(resolved1.request.url, resolved2.request.url)
        XCTAssertEqual(resolved1.request.url, "https://www.apple.com/0?index=1")
        XCTAssertEqual(resolved2.request.url, "https://www.apple.com/3?index=2")
    }

    func testStored_whenMultiplePath_shouldIndexBeOneAndPathZero() async throws {
        // Given
        final class Factory: Index, IndexFactory {
            static let producer = IndexProducer()

            init() {
                super.init(Self.producer)
            }
        }

        let toolbox = toolbox(Factory.self)

        // When
        let resolved1 = try await resolve(TestProperty {
            toolbox.MultiplePath()
        })

        let resolved2 = try await resolve(TestProperty {
            toolbox.MultiplePath()
        })

        // Then
        XCTAssertEqual(Factory.producer.index, 2)
        XCTAssertEqual(resolved1.request.url, resolved2.request.url)
        XCTAssertEqual(resolved1.request.url, "https://www.apple.com/0/1")
    }

    func testStored_whenCombined_shouldRestoreEachOne() async throws {
        // Given
        final class Factory: Index, IndexFactory {
            static let producer = IndexProducer()

            init() {
                super.init(Self.producer)
            }
        }

        let toolbox = toolbox(Factory.self)

        // When
        let resolved1 = try await resolve(TestProperty {
            toolbox.CombinedPath()
        })

        let resolved2 = try await resolve(TestProperty {
            toolbox.CombinedPath()
        })

        // Then
        XCTAssertEqual(Factory.producer.index, 3)
        XCTAssertEqual(resolved1.request.url, resolved2.request.url)
        XCTAssertEqual(resolved1.request.url, "https://www.apple.com/0/1.2")
    }
}

extension StoredObjectTests {

    func toolbox<Factory: IndexFactory>(_ factory: Factory.Type) -> StoredObjectToolbox<Factory>.Type {
        StoredObjectToolbox<Factory>.self
    }
}
