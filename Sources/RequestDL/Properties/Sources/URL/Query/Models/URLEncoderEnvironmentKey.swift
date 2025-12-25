/*
 See LICENSE for this package's licensing information.
*/

import Foundation

private struct URLEncoderEnvironmentKey: RequestEnvironmentKey {
    static let defaultValue = URLEncoder()
}

extension RequestEnvironmentValues {

    var urlEncoder: URLEncoder {
        get { self[URLEncoderEnvironmentKey.self] }
        set { self[URLEncoderEnvironmentKey.self] = newValue }
    }
}

extension Property {

    /**
    Configures the URL encoder for the property.

    - Parameter encoder: The `URLEncoder` instance to be used for URL encoding.
    - Returns: A property that applies the specified URL encoder to the environment.
    */
    public func urlEncoder(_ encoder: URLEncoder) -> some Property {
        environment(\.urlEncoder, encoder)
    }
}
