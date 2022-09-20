import Foundation

// swiftlint:disable type_name
@available(iOS, introduced: 1000, message: "This method and protocol will change")
@available(macOS, introduced: 1000, message: "This method and protocol will change")
@available(watchOS, introduced: 1000, message: "This method and protocol will change")
@available(tvOS, introduced: 1000, message: "This method and protocol will change")
@available(iOS 15, macOS 12, watchOS 8, tvOS 15, *)
public struct _BytesTargetTask: TargetTaskType {

    init() {}

    public func response<Target: RequestDL.Target>(
        for target: Target
    ) async throws -> TaskResult<URLSession.AsyncBytes> {
        try await BytesTask(content: target.reduced).response()
    }
}

@available(iOS, introduced: 1000, message: "This method and protocol will change")
@available(macOS, introduced: 1000, message: "This method and protocol will change")
@available(watchOS, introduced: 1000, message: "This method and protocol will change")
@available(tvOS, introduced: 1000, message: "This method and protocol will change")
@available(iOS 15, macOS 12, watchOS 8, tvOS 15, *)
public extension TargetTaskType where Self == _BytesTargetTask {

    static var bytes: _BytesTargetTask {
        .init()
    }
}
