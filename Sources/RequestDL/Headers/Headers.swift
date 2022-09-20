import Foundation

public enum Headers {}

extension Headers {

    struct Object: NodeObject {
        let key: String
        let value: Any

        init(_ key: String, _ value: Any) {
            self.key = key
            self.value = value
        }

        func makeRequest(_ request: inout URLRequest, configuration: inout URLSessionConfiguration, delegate: DelegateProxy) {
            request.setValue("\(value)", forHTTPHeaderField: key)
        }
    }
}
