import Foundation

@propertyWrapper
public struct RequestBackgroundAdaptor {

    public init() {}

    public var wrappedValue: () -> Void {
        get { fatalError("get not implemented") }
        set { BackgroundService.shared.completionHandler = newValue }
    }
}

class BackgroundService {

    static let shared = BackgroundService()

    var completionHandler: (() -> Void)?
}
