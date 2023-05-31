/*
 See LICENSE for this package's licensing information.
*/

import Foundation

private struct URLEncoderEnvironmentKey: PropertyEnvironmentKey {
    static var defaultValue = URLEncoder()
}

extension PropertyEnvironmentValues {

    var urlEncoder: URLEncoder {
        get { self[URLEncoderEnvironmentKey.self] }
        set { self[URLEncoderEnvironmentKey.self] = newValue }
    }
}

extension Property {

    public func urlEncoder(_ encoder: URLEncoder) -> some Property {
        environment(\.urlEncoder, encoder)
    }
}
