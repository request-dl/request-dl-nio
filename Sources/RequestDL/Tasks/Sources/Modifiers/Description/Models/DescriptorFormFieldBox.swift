//
// See LICENSE for this package's licensing information.
//

/// Where `FormNode` deposits a ``FormFieldDescriptor`` per field while a description pass is
/// running.
///
/// A fresh instance is created per ``RawTask/description(_:)`` call and only ever touched by the
/// single sequential `await`-chain that walks the node graph for that one call — never shared
/// across calls, never accessed concurrently — so this needs no lock despite being a mutable
/// reference type carried through `RequestEnvironmentValues` (via `_PropertyInputs.environment`)
/// into `FormNode`.
final class DescriptorFormFieldBox: @unchecked Sendable {

    // MARK: - Internal properties

    var fields: [FormFieldDescriptor] = []
}
