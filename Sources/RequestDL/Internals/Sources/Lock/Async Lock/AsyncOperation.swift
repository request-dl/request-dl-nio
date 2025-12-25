import Foundation

final class AsyncOperation: @unchecked Sendable {

    private enum State {
        case idle
        case scheduled(UnsafeContinuation<Void, Never>)
        case cancelled
    }

    var isScheduled: Bool {
        lock.withLock {
            if case .scheduled = _state {
                return true
            } else {
                return false
            }
        }
    }

    private let lock = Lock()
    private var _state: State = .idle

    init() {}

    func schedule(_ continuation: UnsafeContinuation<Void, Never>) {
        lock.withLock {
            if case .idle = _state {
                _state = .scheduled(continuation)
            }
        }
    }

    func resume() {
        lock.withLock {
            if case .scheduled(let continuation) = _state {
                _state = .idle
                continuation.resume()
            }
        }
    }

    func cancelled() {
        lock.withLock {
            _state = .cancelled
        }
    }
}
