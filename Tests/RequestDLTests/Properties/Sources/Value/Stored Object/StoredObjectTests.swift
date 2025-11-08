/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct StoredObjectTests {

    typealias Toolbox = StoredObjectToolbox

    @Test
    func stored_whenPath_shouldIndexBeOneAndPathZero() async throws {
        // Given
        final class Factory: Index, IndexFactory, @unchecked Sendable {
            @MainActor
            static let producer = IndexProducer()

            init() {
                super.init(MainActor.sync {
                    Self.producer
                })
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
        #expect(MainActor.sync { Factory.producer }.index == 1)
        #expect(resolved1.request.url == resolved2.request.url)
        #expect(resolved1.request.url == "https://www.apple.com/0")
    }

    @Test
    func stored_whenPathDifferentPosition_shouldBeNotEqual() async throws {
        // Given
        final class Factory: Index, IndexFactory, @unchecked Sendable {
            @MainActor
            static let producer = IndexProducer()

            init() {
                super.init(MainActor.sync {
                    Self.producer
                })
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
        #expect(MainActor.sync { Factory.producer }.index == 1)
        #expect(resolved1.request.url == resolved2.request.url)
        #expect(resolved1.request.url == "https://www.google.com/0")
        #expect(resolved2.request.url == "https://www.google.com/0")
    }

    @Test
    func stored_whenPathWithEqualNamespace() async throws {
        // Given
        final class Factory: Index, IndexFactory, @unchecked Sendable {
            @MainActor
            static let producer = IndexProducer()

            init() {
                super.init(MainActor.sync {
                    Self.producer
                })
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
        #expect(MainActor.sync { Factory.producer }.index == 1)
        #expect(resolved1.request.url == resolved2.request.url)
        #expect(resolved1.request.url == "https://www.apple.com/0")
    }

    @Test
    func stored_whenPathWithDifferentNamespace() async throws {
        // Given
        final class Factory: Index, IndexFactory, @unchecked Sendable {
            @MainActor
            static let producer = IndexProducer()

            init() {
                super.init(MainActor.sync {
                    Self.producer
                })
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
        #expect(MainActor.sync { Factory.producer }.index == 2)
        #expect(resolved1.request.url == "https://www.apple.com/0")
        #expect(resolved2.request.url == "https://www.apple.com/1")
    }

    @Test
    func stored_whenPathQuery_shouldURLContainsZeroAndOnes() async throws {
        // Given
        final class Factory: Index, IndexFactory, @unchecked Sendable {
            @MainActor
            static let producer = IndexProducer()

            init() {
                super.init(MainActor.sync {
                    Self.producer
                })
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
        #expect(MainActor.sync { Factory.producer }.index == 2)
        #expect(resolved1.request.url == resolved2.request.url)
        #expect(resolved1.request.url == "https://www.apple.com/0?index=1")
    }

    @Test
    func stored_whenPathQueryDifferentPosition_shouldBeNotEqual() async throws {
        // Given
        final class Factory: Index, IndexFactory, @unchecked Sendable {
            @MainActor
            static let producer = IndexProducer()

            init() {
                super.init(MainActor.sync {
                    Self.producer
                })
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
        #expect(MainActor.sync { Factory.producer }.index == 4)
        #expect(resolved1.request.url != resolved2.request.url)
        #expect(resolved1.request.url == "https://www.apple.com/0?index=1")
        #expect(resolved2.request.url == "https://www.apple.com/3?index=2")
    }

    @Test
    func stored_whenMultiplePath_shouldIndexBeOneAndPathZero() async throws {
        // Given
        final class Factory: Index, IndexFactory, @unchecked Sendable {
            @MainActor
            static let producer = IndexProducer()

            init() {
                super.init(MainActor.sync {
                    Self.producer
                })
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
        #expect(MainActor.sync { Factory.producer }.index == 2)
        #expect(resolved1.request.url == resolved2.request.url)
        #expect(resolved1.request.url == "https://www.apple.com/0/1")
    }

    @Test
    func stored_whenCombined_shouldRestoreEachOne() async throws {
        // Given
        final class Factory: Index, IndexFactory, @unchecked Sendable {
            @MainActor
            static let producer = IndexProducer()

            init() {
                super.init(MainActor.sync {
                    Self.producer
                })
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
        #expect(MainActor.sync { Factory.producer }.index == 3)
        #expect(resolved1.request.url == resolved2.request.url)
        #expect(resolved1.request.url == "https://www.apple.com/0/1.2")
    }
}

extension StoredObjectTests {

    func toolbox<Factory: IndexFactory>(_ factory: Factory.Type) -> StoredObjectToolbox<Factory>.Type {
        StoredObjectToolbox<Factory>.self
    }
}
