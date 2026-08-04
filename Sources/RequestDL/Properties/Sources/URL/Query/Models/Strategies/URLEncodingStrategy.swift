//
// See LICENSE for this package's licensing information.
//

protocol URLEncodingStrategy: Sendable {

    func encode(in encoder: URLEncoder.Encoder) throws
}
