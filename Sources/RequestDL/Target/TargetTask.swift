import Foundation

@available(iOS, introduced: 1000, message: "This method and protocol will change")
@available(macOS, introduced: 1000, message: "This method and protocol will change")
@available(watchOS, introduced: 1000, message: "This method and protocol will change")
@available(tvOS, introduced: 1000, message: "This method and protocol will change")
public struct TargetTask<TaskType: TargetTaskType>: Task {

    // swiftlint:disable identifier_name
    public let _response: () async throws -> TaskType.Element

    public init<Target: RequestDL.Target>(_ target: Target, _ type: TaskType) {
        _response = {
            try await type.response(for: target)
        }
    }

    public func response() async throws -> TaskType.Element {
        try await _response()
    }
}
