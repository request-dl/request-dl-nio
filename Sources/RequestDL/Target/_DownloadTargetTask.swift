import Foundation

@available(iOS, introduced: 1000, message: "This method and protocol will change")
@available(macOS, introduced: 1000, message: "This method and protocol will change")
@available(watchOS, introduced: 1000, message: "This method and protocol will change")
@available(tvOS, introduced: 1000, message: "This method and protocol will change")
// swiftlint:disable type_name
public struct _DownloadTargetTask: TargetTaskType {

    private let save: (URL) -> Void

    init(save: @escaping (URL) -> Void) {
        self.save = save
    }

    public func response<Target: RequestDL.Target>(for target: Target) async throws -> TaskResult<URL> {
        try await DownloadTask(save: save, content: target.reduced).response()
    }
}

@available(iOS, introduced: 1000, message: "This method and protocol will change")
@available(macOS, introduced: 1000, message: "This method and protocol will change")
@available(watchOS, introduced: 1000, message: "This method and protocol will change")
@available(tvOS, introduced: 1000, message: "This method and protocol will change")
public extension TargetTaskType where Self == _DownloadTargetTask {

    static func download(_ save: @escaping (URL) -> Void) -> _DownloadTargetTask {
        .init(save: save)
    }
}
