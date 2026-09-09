//
// See LICENSE for this package's licensing information.
//

private struct DescriptorFormFieldBoxRequestEnvironmentKey: RequestEnvironmentKey {

    static var defaultValue: DescriptorFormFieldBox? {
        nil
    }
}

extension RequestEnvironmentValues {

    /// Non-`nil` while a ``TaskDescriptor`` pass is resolving — never set by a caller directly,
    /// only by ``RawTask/description(_:)`` around its own `Resolve(...).partiallyBuild()` call.
    var descriptorFormFields: DescriptorFormFieldBox? {
        get { self[DescriptorFormFieldBoxRequestEnvironmentKey.self] }
        set { self[DescriptorFormFieldBoxRequestEnvironmentKey.self] = newValue }
    }
}
