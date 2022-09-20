import Foundation

extension Timeout {

    public struct Source: OptionSet {
        public static let request  = Source(rawValue: 1 << 0)
        public static let resource = Source(rawValue: 1 << 1)

        public static let all: Self = [.request, .resource]

        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }
    }
}
