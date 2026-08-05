//
// See LICENSE for this package's licensing information.
//

protocol URLSingleEncodingStrategy: Sendable {

    associatedtype Value: Sendable

    func encode(_ value: Value, in encoder: URLEncoder.Encoder) throws
}
