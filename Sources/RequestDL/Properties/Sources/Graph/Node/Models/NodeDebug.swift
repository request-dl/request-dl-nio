//
// See LICENSE for this package's licensing information.
//

struct NodeDebug {

    // MARK: - Inner types

    private enum Layout {
        case object
        case enumCase
        case collection
        case tuple
    }

    // MARK: - Private properties

    private var isType: Bool {
        [.class, .enum, .struct].contains(mirror.displayStyle)
    }

    private var layout: Layout {
        switch mirror.displayStyle {
        case .enum:
            return .enumCase
        case .collection, .set, .dictionary:
            return .collection
        case .tuple:
            return .tuple
        default:
            return .object
        }
    }

    private let object: Any
    private let mirror: Mirror
    private let children: [(label: String?, value: Any)]

    // MARK: - Inits

    init(_ object: Any) {
        let mirror = Mirror(reflecting: object)

        self.object = object
        self.mirror = mirror
        // Was a computed property remapping the mirror, read twice per `describe()`.
        self.children = mirror.children.map { ($0.label, $0.value) }
    }

    // MARK: - Internal methods

    func describe() -> String {
        if isType, let customDebug = object as? CustomDebugStringConvertible {
            return customDebug.debugDescription
        }

        guard !children.isEmpty else {
            return "\(mirror.displayStyle == .enum ? "." : "")\(String(describing: object))"
        }

        let title = titleFormatted()
        let reducedChildren = reducedChildren()

        guard layout != .object else {
            let value =
                reducedChildren
                .joined(separator: ",\n")
                .debug_shiftLines()

            return format(title, value)
        }

        guard reducedChildren.contains(where: { $0.contains("\n") }), layout != .enumCase else {
            return format(title, reducedChildren.joined(separator: ", "))
        }

        let values = reducedChildren.joined(separator: ",\n")
        return format(title, "\n\(values.debug_shiftLines())\n")
    }

    // MARK: - Private methods

    /// Assembles the description from its parts.
    ///
    /// This used to reverse the format string, the title and the value, run them through
    /// `String(format:)`, then reverse the result, purely to get two `%@` in the opposite
    /// order. Interpolation does that directly, and it drops a dependency on `%@` bridging,
    /// which is the weakest part of `String(format:)` on the non Darwin platforms this package
    /// supports.
    private func format(_ title: String, _ value: String) -> String {
        switch layout {
        case .enumCase:
            return "\(title).\(value)"
        case .collection:
            return "[\(value)]"
        case .tuple:
            return "(\(value))"
        case .object:
            return "\(title) {\n\(value)\n}"
        }
    }

    private func reducedChildren() -> [String] {
        children.map {
            let value = NodeDebug($1).describe()

            guard let label = $0 else {
                return value
            }

            switch mirror.displayStyle {
            case .enum:
                if value.hasPrefix("(") {
                    return "\(label)\(value)"
                } else if value.contains("\n") {
                    let formatted = value.debug_shiftLines()
                    return "\(label)(\n\(formatted)\n)"
                } else {
                    return "\(label)(\(value))"
                }
            case .collection, .set, .tuple:
                return "\(value)"
            case .dictionary:
                return "\(label): \(value)"
            default:
                return "\(label) = \(value)"
            }
        }
    }

    private func titleFormatted() -> String {
        let title = String(describing: type(of: object))

        switch layout {
        case .collection:
            return title.split(separator: "<")
                .first
                .map { "\($0)" } ?? title
        case .tuple:
            return "Tuple"
        case .enumCase, .object:
            return title
        }
    }
}
