/*
 See LICENSE for this package's licensing information.
*/

import Foundation

protocol URLEncodingStrategy: Sendable {

    func encode(in encoder: URLEncoder.Encoder) throws
}
