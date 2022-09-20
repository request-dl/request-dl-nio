import Foundation

public struct FormFile: Request {

    public typealias Body = Never

    let path: Url
    let key: String?
    let fileManager: FileManager
    let contentType: ContentType

    public init(
        key: String = "",
        _ url: Url,
        withType contentType: ContentType,
        _ fileManager: FileManager = .default
    ) {
        self.key = key.isEmpty ? nil : key
        self.path = url
        self.fileManager = fileManager
        self.contentType = contentType
    }

    public init(
        key: String = "",
        _ url: Url,
        _ fileManager: FileManager = .default
    ) {
        self.key = key.isEmpty ? nil : key
        self.path = url
        self.fileManager = fileManager

        guard let fileExtension = url.absoluteString.split(separator: ".").last else {
            self.contentType = .custom("any")
            return
        }

        self.contentType = .allCases.first(where: {
            $0.rawValue.contains(fileExtension)
        }) ?? .custom("\(fileExtension)")
    }

    public var body: Never {
        Never.bodyException()
    }
}

extension FormFile: PrimitiveRequest {

    func makeObject() -> FormObject {
        .init(.file(self))
    }
}
