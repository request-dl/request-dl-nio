//
// See LICENSE for this package's licensing information.
//

/// A single event frame parsed from a `text/event-stream` (Server-Sent Events) response body.
///
/// Conforms to the [WHATWG event stream interpretation](https://html.spec.whatwg.org/multipage/server-sent-events.html#event-stream-interpretation):
/// consecutive `data:` lines belonging to the same frame are joined with `"\n"`, comment lines
/// (starting with `:`) are dropped, and a frame with no `data:` line at all produces no event.
///
/// - Note: Unlike the browser `EventSource` API, `retry` is exposed directly on the event instead of
/// silently updating a reconnection timer -- this type performs no reconnection of its own, so the value
/// is surfaced for the caller to act on if desired.
public struct ServerSentEvent: Sendable, Hashable {

    /// The event's `id:` field, or `nil` if the stream has not sent one yet.
    ///
    /// Once set, the value persists across subsequent events until a new `id:` line is received,
    /// mirroring the "last event ID" behavior of the specification.
    public let id: String?

    /// The event's `event:` field, defaulting to `"message"` when the stream omits it.
    public let event: String

    /// The event's payload, formed by joining every `data:` line in the frame with `"\n"`.
    public let data: String

    /// The reconnection time, in milliseconds, from the most recently seen `retry:` line.
    public let retry: Int?
}
