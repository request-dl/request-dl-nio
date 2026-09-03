//
// See LICENSE for this package's licensing information.
//

import Testing

@_spi(Private) @testable import RequestDL

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

struct GroupTaskTests {

    @Test
    func groupTask() async throws {
        // Given
        let items = Array(0..<10)

        // When
        let result = try await GroupTask(items) { index in
            MockedTask {
                BaseURL("localhost")
                Payload(data: Data("\(index)".utf8))
            }
            .collectData()
        }
        .result()

        // Then
        #expect(result.keys.count == items.count)
        #expect(
            items.allSatisfy {
                switch result[$0] {
                case .failure, .none:
                    return false
                case .success(let result):
                    return result.payload == Data("\($0)".utf8)
                }
            }
        )
    }

    private struct NumberTask: RequestTask {

        @RequestEnvironment(\.number) var number

        func result() async throws -> Int {
            number
        }
    }

    @Test
    func groupTask_whenElementOverridesEnvironment_elementValueWinsOverGroupValue() async throws {
        // Given
        let items = Array(0..<3)

        // When
        let result = try await GroupTask(items) { index in
            index == 1
                ? NumberTask().environment(\.number, 99).eraseToAnyTask()
                : NumberTask().eraseToAnyTask()
        }
        .environment(\.number, 2)
        .result()

        // Then
        #expect(result[0].map { try? $0.get() } == 2)
        #expect(result[1].map { try? $0.get() } == 99)
        #expect(result[2].map { try? $0.get() } == 2)
    }
}

private struct NumberKey: RequestEnvironmentKey {
    static let defaultValue = 1
}

extension RequestEnvironmentValues {

    fileprivate var number: Int {
        get { self[NumberKey.self] }
        set { self[NumberKey.self] = newValue }
    }
}
