//
// See LICENSE for this package's licensing information.
//

private struct RequestControllersRequestEnvironmentKey: RequestEnvironmentKey {

    static var defaultValue: [RequestController] {
        []
    }
}

extension RequestEnvironmentValues {

    /// Queued by ``RequestTask/controller(_:)``; never touched directly.
    ///
    /// `RawTask` is the only thing that ever reads this: when it isn't empty, it gives the
    /// execution a transfer control and attaches it to every controller here. A list, not a single
    /// value, so two `.controller(_:)` calls in one chain both apply.
    var requestControllers: [RequestController] {
        get { self[RequestControllersRequestEnvironmentKey.self] }
        set { self[RequestControllersRequestEnvironmentKey.self] = newValue }
    }
}
