//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

/// A protocol that defines the properties and methods required for a primitive task result.
public protocol TaskResultPrimitive: Sendable {

    var head: ResponseHead { get }
}

/// A structure that represents the result of a task.
public struct TaskResult<Element: Sendable>: TaskResultPrimitive {

    // MARK: - Public properties

    /// The response head of the task result.
    public let head: ResponseHead

    /// The payload of the task result.
    public let payload: Element

    /// What the request measured on the wire, or `nil` when nothing went over it, as when the response
    /// came from the cache or was mocked.
    ///
    /// It is read when asked for, so it reflects the transactions that had ended by then. For a
    /// `TaskResult<Data>` that is all of them, since the body has been collected by the time the
    /// result exists. For a `TaskResult<AsyncBytes>` the last one only ends once the body has been
    /// consumed, so read it after that to get the complete picture.
    public var metrics: RequestMetrics? {
        guard let transactions = metricsCollector?.transactions(), !transactions.isEmpty else {
            return nil
        }

        return RequestMetrics(transactions)
    }

    // MARK: - Private properties

    private let metricsCollector: Internals.RequestMetricsCollector?

    // MARK: - Inits

    ///
    /// Initializes a new instance of the TaskResult struct.
    ///
    /// - Parameters:
    ///    - head: The response head of the task result.
    ///    - payload: The payload of the task result.
    ///
    public init(
        head: ResponseHead,
        payload: Element
    ) {
        self.head = head
        self.payload = payload
        self.metricsCollector = nil
    }

    init(
        head: ResponseHead,
        payload: Element,
        metrics: Internals.RequestMetricsCollector?
    ) {
        self.head = head
        self.payload = payload
        self.metricsCollector = metrics
    }

    // MARK: - Internal methods

    /// The same result carrying another payload, for the modifiers that transform it: the head and
    /// the metrics are the response's own, so they go along unchanged.
    func withPayload<NewElement: Sendable>(_ payload: NewElement) -> TaskResult<NewElement> {
        TaskResult<NewElement>(
            head: head,
            payload: payload,
            metrics: metricsCollector
        )
    }
}
