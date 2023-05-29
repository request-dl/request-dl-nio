/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/// Enum defining the strategy for handling headers.
public enum HeaderStrategy: Sendable {

    /// The headers will be added to the existing headers.
    case adding

    /// The headers will be replaced with the new headers.
    case setting
}
