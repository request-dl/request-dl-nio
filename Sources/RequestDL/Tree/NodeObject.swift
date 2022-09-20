import Foundation

protocol NodeObject {

    func makeRequest(
        _ request: inout URLRequest,
        configuration: inout URLSessionConfiguration,
        delegate: DelegateProxy
    )
}
