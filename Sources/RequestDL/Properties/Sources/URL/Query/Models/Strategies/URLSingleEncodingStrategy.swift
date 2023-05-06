/*
 See LICENSE for this package's licensing information.
*/

import Foundation

protocol URLSingleEncodingStrategy {

    associatedtype Value

    func encode(_ value: Value, in encoder: URLEncoder.Encoder) throws
}
