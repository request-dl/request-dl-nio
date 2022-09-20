import Foundation

extension Task {

    public func ping(_ times: Int = 1, debug: Bool = true) async throws {
        guard times > 0 else {
            fatalError()
        }

        for index in 0 ..< times {
            if debug {
                print("[Request] Pinging \(index + 1) started")
            }

            let time = Date()
            _ = try await response()

            if debug {
                let interval = Date().timeIntervalSince(time)

                print("[Request] Pinging \(index + 1) success \(String(format: "%0.3f", interval))s")
            }
        }
    }
}
