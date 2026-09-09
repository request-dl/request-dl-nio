//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

/// Installs an already-built `RequestConfiguration` as-is, bypassing every other node — and,
/// optionally, an edit to `Make.sessionConfiguration` alongside it, the same way `Session`'s own
/// node does (`configuration?(&make.sessionConfiguration)`), for the handful of curl flags that
/// are session-level rather than request-level (`-L`, `-k`, `-x`, `--resolve`, `--compressed`).
///
/// `CURLCommandParser` builds a `RequestConfiguration` directly from a parsed curl command line
/// rather than composing a `@PropertyBuilder` tree of `BaseURL`/`Headers`/etc. — there is no
/// per-flag `Property` to declare. This is the bridge back into `RawTask`/`Resolve`, so a parsed
/// command still goes through the same session/cache/executor/tracing pipeline every other task
/// uses instead of duplicating it.
struct RawRequestConfigurationProperty: Property {

    private struct Node: PropertyNode {

        let configuration: RequestConfiguration
        let sessionConfigurationEdit: (@Sendable (inout Internals.Session.Configuration) -> Void)?

        func make(_ make: inout Make) async throws {
            make.requestConfiguration = configuration
            sessionConfigurationEdit?(&make.sessionConfiguration)
        }
    }

    // MARK: - Public properties

    var body: Never {
        bodyException()
    }

    // MARK: - Internal properties

    let configuration: RequestConfiguration
    let sessionConfigurationEdit: (@Sendable (inout Internals.Session.Configuration) -> Void)?

    // MARK: - Inits

    init(
        configuration: RequestConfiguration,
        sessionConfigurationEdit: (@Sendable (inout Internals.Session.Configuration) -> Void)? = nil
    ) {
        self.configuration = configuration
        self.sessionConfigurationEdit = sessionConfigurationEdit
    }

    // MARK: - Public static methods

    static func _makeProperty(
        property: _GraphValue<RawRequestConfigurationProperty>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()
        return .leaf(
            Node(
                configuration: property.configuration,
                sessionConfigurationEdit: property.sessionConfigurationEdit
            )
        )
    }
}
