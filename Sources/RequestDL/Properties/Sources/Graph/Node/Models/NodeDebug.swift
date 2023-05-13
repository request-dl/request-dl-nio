/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct NodeDebug {

    // MARK: - Private properties

    private var isType: Bool {
        [.class, .enum, .struct].contains(mirror.displayStyle)
    }

    private func defaultDebugDescription() -> String {
        String(describing: object)
    }

    private var children: [(label: String?, value: Any)] {
        mirror.children.map {
            ($0.label, $0.value)
        }
    }

    private let object: Any
    private let mirror: Mirror

    // MARK: - Inits

    init(_ object: Any) {
        self.object = object
        self.mirror = .init(reflecting: object)
    }

    // MARK: - Internal methods

    func describe() -> String {
        if isType, let customDebug = object as? CustomDebugStringConvertible {
            return customDebug.debugDescription
        }

        guard !children.isEmpty else {
            return "\(mirror.displayStyle == .enum ? "." : "")\(defaultDebugDescription())"
        }

        let title = titleFormatted()
        let reducedChildren = reducedChildren()
        let output = outputFormat()

        if output.contains("\n") {
            let value = reducedChildren
                .joined(separator: ",\n")
                .debug_shiftLines()

            return Self.format(output, title, value)
        } else {
            if reducedChildren.contains(where: { $0.contains("\n") }) && mirror.displayStyle != .enum {
                let values = reducedChildren.joined(separator: ",\n")
                return Self.format(output, title, "\n\(values.debug_shiftLines())\n")
            } else {
                return Self.format(output, title, reducedChildren.joined(separator: ", "))
            }
        }
    }

    // MARK: - Private static methods

    private static func format(_ output: String, _ title: String, _ value: String) -> String {
        reverse(String(
            format: reverse(output).replacingOccurrences(of: "@%", with: "%@"),
            reverse(value),
            reverse(title)
        ))
    }

    private static func reverse(_ string: String) -> String {
        String(string.reversed())
    }

    // MARK: - Private methods

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
            case .none, .class, .struct, .optional:
                return "\(label) = \(value)"
            @unknown default:
                return "\(label) = \(value)"
            }
        }
    }

    private func outputFormat() -> String {
        switch mirror.displayStyle {
        case .enum:
            return "%@.%@"
        case .collection, .set, .dictionary:
            return "[%@]"
        case .tuple:
            return "(%@)"
        default:
            return "%@ {\n%@\n}"
        }
    }

    private func titleFormatted() -> String {
        let title = String(describing: type(of: object))

        switch mirror.displayStyle {
        case .collection, .set, .dictionary:
            return title.split(separator: "<")
                .first
                .map { "\($0)" } ?? title
        case .tuple:
            return "Tuple"
        default:
            return title
        }
    }
}
