import Foundation

public struct MockedTask: Task {

    private let statusCode: Int
    private let headers: [String: String]?
    private let string: String

    public init(
        statusCode: Int = 200,
        headers: [String: String]? = nil,
        _ string: () -> String
    ) {
        self.statusCode = statusCode
        self.headers = headers
        self.string = string()
    }
}

extension MockedTask {

    public func response() async throws -> TaskResult<Data> {
        guard let data = string.data(using: .utf8) else {
            throw ErrorKeys.encoding
        }

        guard let response = HTTPURLResponse(
            url: FileManager.default.temporaryDirectory,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: headers
        ) else { throw ErrorKeys.httpResponse }

        return .init(response: response, data: data)
    }
}

extension MockedTask {

    enum ErrorKeys: Error {
        case encoding
        case httpResponse
    }
}
