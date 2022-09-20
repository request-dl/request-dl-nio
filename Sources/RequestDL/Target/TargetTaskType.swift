import Foundation

@available(iOS, introduced: 1000, message: "This method and protocol will change")
@available(macOS, introduced: 1000, message: "This method and protocol will change")
@available(watchOS, introduced: 1000, message: "This method and protocol will change")
@available(tvOS, introduced: 1000, message: "This method and protocol will change")
public protocol TargetTaskType {

    associatedtype Element

    func response<Target: RequestDL.Target>(for target: Target) async throws -> Element
}
