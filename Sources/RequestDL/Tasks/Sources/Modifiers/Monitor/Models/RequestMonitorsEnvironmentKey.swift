//
// See LICENSE for this package's licensing information.
//

private struct RequestMonitorsRequestEnvironmentKey: RequestEnvironmentKey {

    static var defaultValue: [any RequestMonitor] {
        []
    }
}

extension RequestEnvironmentValues {

    /// Queued by ``RequestTask/monitor(_:)``; never touched directly.
    ///
    /// `RawTask` is the only thing that ever reads this: when it isn't empty, it observes the
    /// execution and tells every monitor here about it. A list, so two `.monitor(_:)` calls in one
    /// chain both apply.
    var requestMonitors: [any RequestMonitor] {
        get { self[RequestMonitorsRequestEnvironmentKey.self] }
        set { self[RequestMonitorsRequestEnvironmentKey.self] = newValue }
    }
}
