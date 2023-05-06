/*
 See LICENSE for this package's licensing information.
*/

import Foundation

private struct URLEncoderEnvironmentKey: EnvironmentKey {
    static var defaultValue = URLEncoder()
}

extension EnvironmentValues {

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
