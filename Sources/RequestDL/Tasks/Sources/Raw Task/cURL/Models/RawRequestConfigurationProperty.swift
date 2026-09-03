//
// See LICENSE for this package's licensing information.
//

/// Installs an already-built `RequestConfiguration` as-is, bypassing every other node.
///
/// `CURLCommandParser` builds a `RequestConfiguration` directly from a parsed curl command line
/// rather than composing a `@PropertyBuilder` tree of `BaseURL`/`Headers`/etc. — there is no
/// per-flag `Property` to declare. This is the bridge back into `RawTask`/`Resolve`, so a parsed
/// command still goes through the same session/cache/executor/tracing pipeline every other task
/// uses instead of duplicating it.
struct RawRequestConfigurationProperty: Property {

    private struct Node: PropertyNode {

        let configuration: RequestConfiguration

        func make(_ make: inout Make) async throws {
            make.requestConfiguration = configuration
        }
    }

    // MARK: - Public properties

    var body: Never {
        bodyException()
    }

    // MARK: - Internal properties

    let configuration: RequestConfiguration

    // MARK: - Public static methods

    static func _makeProperty(
        property: _GraphValue<RawRequestConfigurationProperty>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()
        return .leaf(
            Node(configuration: property.configuration)
        )
    }
}
