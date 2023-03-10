/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct PartFormRawValue {

    let data: Data
    let headers: [String: Any]

    init(_ data: Data, forHeaders headers: [String: Any]) {
        self.data = data
        self.headers = headers
    }
}

var kContentDisposition: String {
    "Content-Disposition"
}

func kContentDispositionValue(
    _ fileName: String?,
    forKey key: String
) -> String {
    if let fileName {
        return "form-data; name=\"\(key)\"; filename=\"\(fileName)\""
    } else {
        return "form-data; name=\"\(key)\""
    }
}
