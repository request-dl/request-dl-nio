/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing

@testable import RequestDL

struct LocalDataCacheTrait: TestTrait, SuiteTrait, TestScoping {

    enum Mode {
        case main
        case autogenerate
    }

    let isRecursive: Bool = true

    private let dataCache: @Sendable () -> DataCache

    init(_ mode: Mode) {
        switch mode {
        case .main:
            dataCache = { .init() }
        case .autogenerate:
            dataCache = { .init(suiteName: UUID().uuidString) }
        }
    }

    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        try await DataCache.withTaskLocalDataCache(
            dataCache: dataCache,
            operation: function
        )
    }
}

extension Trait where Self == LocalDataCacheTrait {

    static var localDataCache: Self {
        .init(.main)
    }

    static func localDataCache(_ mode: LocalDataCacheTrait.Mode) -> Self {
        .init(mode)
    }
}
