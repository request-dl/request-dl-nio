import Foundation

enum FormUtils {}

extension FormUtils {

    public static func buildBody(_ data: [Data], with boundary: String) -> Data {
        guard let last = data.last else {
            return Data()
        }

        var data = data.dropLast().reduce(Data()) {
            var data = $0
            data.append(header(boundary))
            data.append($1)
            data.append(middle)
            return data
        }

        data.append(header(boundary))
        data.append(last)
        data.append(footer(boundary))

        return data
    }
}

internal extension FormUtils {

    private static var random: UInt32 {
        .random(in: .min ... .max)
    }

    static var boundary: String {
        String(format: "request.boundary.%08x%08x", random, random)
    }

    private static var formData: String {
        ContentType.formData.rawValue
    }

    static var breakLine: String {
        "\r\n"
    }

    static func header(_ boundary: String) -> Data {
        .init("--\(boundary)\(breakLine)".utf8)
    }

    static var middle: Data {
        .init("\(breakLine)".utf8)
    }

    static func footer(_ boundary: String) -> Data {
        .init("\(breakLine)--\(boundary)--\(breakLine)".utf8)
    }

    static func disposition<K, S>(
        _ key: K?,
        _ fileName: S,
        withType contentType: ContentType
    ) -> Data where K: StringProtocol, S: StringProtocol {
        let name = key.map { String($0) } ?? {
            if fileName.contains(".") {
                return fileName
                    .split(separator: ".")
                    .dropLast()
                    .joined(separator: ".")
            } else {
                return "\(fileName)"
            }
        }()

        var contents = Data()

        contents.append(Data("Content-Disposition: \(formData); name=\"\(name)\";".utf8))
        contents.append(Data("filename=\"\(fileName)\"".utf8))
        contents.append(Data(breakLine.utf8))

        contents.append(Data("Content-Type: \(contentType.rawValue)".utf8))
        contents.append(Data(breakLine.utf8))

        return contents
    }

    static func disposition<S>(_ name: S) -> Data where S: StringProtocol {
        Data(
            "Content-Disposition: \(formData); name=\"\(name)\"\(breakLine)".utf8
        )
    }
}
