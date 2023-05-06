/*
 See LICENSE for this package's licensing information.
*/

import Foundation

protocol URLEncodingStrategy {

    func encode(in encoder: URLEncoder.Encoder) throws
}
