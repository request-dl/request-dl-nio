/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/// This struct is marked as internal and is not intended
/// to be used directly by clients of this framework.
public struct _ConditionalContent<
    TrueProperty: Property,
    FalseProperty: Property
>: Property {

    private let option: Option

    init(first property: TrueProperty) {
        option = .first(property)
    }

    init(second property: FalseProperty) {
        option = .second(property)
    }

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    /// This method is used internally and should not be called directly.
    public static func makeProperty(
        _ property: Self,
        _ context: Context
    ) async {
        switch property.option {
        case .first(let property):
            await TrueProperty.makeProperty(property, context)
        case .second(let property):
            await FalseProperty.makeProperty(property, context)
        }
    }
}

extension _ConditionalContent {

    enum Option {
        case first(TrueProperty)
        case second(FalseProperty)
    }
}
