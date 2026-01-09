import Foundation

final class AsyncOperation: @unchecked Sendable {

    enum State: Hashable {
        case waiting
        case finished
        case cancelled
    }

    private enum _State {
        case idle
        case scheduled(UnsafeContinuation<Void, Never>)
        case finished
        case cancelled
    }

    var state: State {
        lock.withLock {
            switch _state {
            case .idle, .scheduled:
                return .waiting
            case .finished:
                return .finished
            case .cancelled:
                return .cancelled
            }
        }
    }

    private let lock = Lock()
    private var _state: _State = .idle

    init() {}

    func schedule(_ continuation: UnsafeContinuation<Void, Never>) {
        lock.withLock {
            if case .idle = _state {
                _state = .scheduled(continuation)
            }
        }
    }

    func resume() {
        let continuation = lock.withLock { () -> UnsafeContinuation<Void, Never>? in
            guard case .scheduled(let continuation) = _state else {
                return nil
            }

            _state = .finished
            return continuation
        }

        continuation?.resume()
    }

    func cancelled() {
        lock.withLock {
            _state = .cancelled
        }
    }
}
