import Foundation

@available(iOS, introduced: 1000, message: "This method and protocol will change")
@available(macOS, introduced: 1000, message: "This method and protocol will change")
@available(watchOS, introduced: 1000, message: "This method and protocol will change")
@available(tvOS, introduced: 1000, message: "This method and protocol will change")
// swiftlint:disable type_name
public struct _DataTargetTask: TargetTaskType {

    init() {}

    public func response<Target: RequestDL.Target>(for target: Target) async throws -> TaskResult<Data> {
        try await DataTask(content: target.reduced).response()
    }
}

@available(iOS, introduced: 1000, message: "This method and protocol will change")
@available(macOS, introduced: 1000, message: "This method and protocol will change")
@available(watchOS, introduced: 1000, message: "This method and protocol will change")
@available(tvOS, introduced: 1000, message: "This method and protocol will change")
public extension TargetTaskType where Self == _DataTargetTask {

    static var data: _DataTargetTask {
        .init()
    }
}
