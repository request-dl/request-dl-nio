/*
 See LICENSE for this package's licensing information.
*/

#if canImport(Darwin)
import Foundation
#else
@preconcurrency import Foundation
#endif

@available(*, deprecated)
struct LiteralMockedTaskPayload: MockedTaskPayload {

    // MARK: - Internal properties

    let statusCode: StatusCode
    let headers: [String: String]?
    let data: Data

    // MARK: - Internal methods

    func result() async throws -> TaskResult<Data> {
        .init(
            head: ResponseHead(
                url: nil,
                status: .init(
                    code: statusCode.rawValue,
                    reason: "Mock status"
                ),
                version: .init(minor: 1, major: 2),
                headers: .init(Array(headers ?? [:])),
                isKeepAlive: false
            ),
            payload: data
        )
    }
}
