/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/// This struct is marked as internal and is not intended
/// to be used directly by clients of this framework.
@available(*, deprecated, renamed: "_EitherContent")
public typealias _ConditionalContent<
    TrueProperty: Property,
    FalseProperty: Property
> = _EitherContent<TrueProperty, FalseProperty>
