/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import AsyncHTTPClient
import NIOCore
import NIOPosix

class SessionTask {

    let response: Internals.AsyncResponse
    private var eventLoopFuture: EventLoopFuture<Void>?
    private var complete: Bool = false

    init(_ response: Internals.AsyncResponse) {
        self.response = response
    }

    func attach(_ eventLoopFuture: EventLoopFuture<Void>) {
        self.eventLoopFuture = eventLoopFuture
    }
}

extension Internals {

    struct Session {

        let provider: SessionProvider
        let configuration: Internals.Session.Configuration
        let manager: SessionManager

        init(
            provider: SessionProvider,
            configuration: Configuration
        ) {
            self.provider = provider
            self.configuration = configuration
            self.manager = .shared
        }

        func request(_ request: Request) async throws -> SessionTask {
            let client = try await manager.client(provider, for: configuration)

            let upload = DataStream<Int>()
            let head = DataStream<ResponseHead>()
            let download = DownloadBuffer(readingMode: configuration.readingMode)

            let delegate = ClientResponseReceiver(
                url: request.url,
                upload: upload,
                head: head,
                download: download
            )

            let response = AsyncResponse(
                upload: upload,
                head: head,
                download: download.stream
            )

            let request = try request.build()

            let eventLoopFuture = await client.execute(
                request: request,
                delegate: delegate
            )

            let sessionTask = SessionTask(response)
            sessionTask.attach(eventLoopFuture)
            return sessionTask
        }
    }
}

extension Internals {

    @RequestActor
    class SessionManager {

        static let lifetime: Int = 5_000_000_000
        static let shared = SessionManager(lifetime: lifetime)

        private let lifetime: Int
        private var table = [String: [Item]]()

        init(lifetime: Int) {
            self.lifetime = lifetime
            scheduleCleanup()
        }

        func client(
            _ provider: SessionProvider,
            for configuration: Internals.Session.Configuration
        ) async throws -> Internals.Client {
            if var items = table[provider.id] {
                if let (index, item) = items.enumerated().first(where: { $1.configuration == configuration }) {
                    items[index] = item.updatingReadAt()
                    table[provider.id] = items
                    return item.client
                }
            }

            let configurationBuilt = try configuration.build()
            let providerBuilt = await EventLoopGroupManager.shared.provider(provider)

            let client = await Internals.Client(
                eventLoopGroupProvider: .shared(providerBuilt),
                configuration: configurationBuilt
            )

            var items = table[provider.id] ?? []

            items.append(.createNew(
                configuration: configuration,
                client: client
            ))

            table[provider.id] = items
            return client
        }
    }
}

extension Internals.SessionManager {

    fileprivate func scheduleCleanup() {
        _Concurrency.Task(priority: .background) {
            try await _Concurrency.Task.sleep(nanoseconds: UInt64(lifetime))
            await cleanupIfNeeded()
            scheduleCleanup()
        }
    }

    private func cleanupIfNeeded() async {
        let now = Date()
        let lifetime = Double(lifetime) / 1_000_000_000

        for (key, items) in table {
            var optionalItems = items as [Internals.Item?]

            for (index, item) in items.enumerated() {
                if await item.client.isRunning {
                    optionalItems[index] = item.updatingReadAt()
                } else if now.distance(to: item.readAt) > lifetime {
                    if (try? await item.client.shutdown()) ?? false {
                        optionalItems[index] = nil
                    }
                }
            }

            let items = optionalItems.compactMap { $0 }
            table[key] = items.isEmpty ? nil : items
        }
    }
}

extension Internals {

    struct Item {
        let configuration: Internals.Session.Configuration
        let client: Internals.Client
        let readAt: Date

        static func createNew(
            configuration: Internals.Session.Configuration,
            client: Internals.Client
        ) -> Item {
            .init(
                configuration: configuration,
                client: client,
                readAt: .init()
            )
        }

        func updatingReadAt() -> Item {
            .init(
                configuration: configuration,
                client: client,
                readAt: .init()
            )
        }
    }
}

@globalActor
actor HTTPClientActor {
    static let shared = HTTPClientActor()
}

extension Internals {

    @HTTPClientActor
    class Client {

        private let manager = RequestManager()
        private let _client: HTTPClient
        private var isClosed: Bool

        init(
            eventLoopGroupProvider: HTTPClient.EventLoopGroupProvider,
            configuration: HTTPClient.Configuration
        ) {
            isClosed = false
            _client = .init(
                eventLoopGroupProvider: eventLoopGroupProvider,
                configuration: configuration
            )
        }

        func execute<Delegate: HTTPClientResponseDelegate>(
            request: HTTPClient.Request,
            delegate: Delegate
        ) -> EventLoopFuture<Delegate.Response> {
            let operation = manager.operation()

            return _client.execute(
                request: request,
                delegate: delegate
            ).futureResult.always { _ in
                _Concurrency.Task {
                    await operation.complete()
                }
            }
        }

        func shutdown() async throws -> Bool {
            guard !isRunning && !isClosed else {
                return false
            }

            try await _client.shutdown()
            isClosed = true
            return true
        }

        var isRunning: Bool {
            manager.isRunning
        }
    }
}

@HTTPClientActor
class RequestManager {

    private let root: Root
    private weak var last: RequestOperation?

    init() {
        let root = Root()

        self.root = root
        self.last = root
    }

    func operation() -> RequestOperation {
        let last = last ?? root
        let operation = RequestOperation()
        operation.connect(to: last)
        self.last = operation
        return operation
    }

    var isRunning: Bool {
        last !== root
    }
}

@HTTPClientActor
class RequestOperation {

    private(set) weak var previous: RequestOperation?
    private(set) var next: RequestOperation?

    init() {}

    func connect(to operation: RequestOperation) {
        operation.next = self
        self.previous = operation
    }

    func complete() {
        previous?.next = next
    }
}

extension RequestManager {

    class Root: RequestOperation {

        override func complete() {
            // TODO: - Missing completion
        }
    }
}
