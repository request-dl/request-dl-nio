/*
 See LICENSE for this package's licensing information.
*/

import Foundation

protocol PropertyNode: CustomDebugStringConvertible {

    func make(_ make: inout Make) async throws
}

extension String {

    private static func shifted(_ shifting: Int) -> String {
        guard shifting > .zero else {
            return ""
        }

        return String(repeating: " ", count: shifting)
    }

    private func debug_regularUpdateLinesByShifting(_ shifting: Int) -> String {
        guard contains("\n") else {
            return self
        }

        return self
            .split(separator: "\n")
            .map { "\(Self.shifted(shifting))\($0)" }
            .joined(separator: "\n")
    }

    func debug_updateLinesByShifting(_ shifting: Int = 4, inline: Bool = true) -> String {
        guard ["}", "]", ")"].contains(last) && inline else {
            return debug_regularUpdateLinesByShifting(shifting)
        }

        let lines = split(separator: "\n")

        guard
            let first = lines.first,
            let last = lines.last,
            first != last
        else { return debug_regularUpdateLinesByShifting(shifting) }

        let shiftedLines = lines[1..<lines.endIndex - 1].map {
            "\(Self.shifted(shifting))\($0)"
        }

        let shiftedLast = "\(Self.shifted(shifting - 4))\(last)"

        return (["\(first)"] + shiftedLines + [shiftedLast])
            .joined(separator: "\n")
    }
}

extension PropertyNode {

    #if DEBUG
    private static func describing(_ property: Any, root: Bool = false) -> String {
        if !root, let custom = property as? CustomDebugStringConvertible {
            return custom.debugDescription
        }

        let mirror = Mirror(reflecting: property)

        if mirror.displayStyle == .optional {
            return String(describing: property)
        }

        guard !mirror.children.isEmpty else {
            if mirror.displayStyle == .enum {
                return ".\(property)"
            } else {
                return "\(property)"
            }
        }

        let title = String(describing: type(of: property))

        let values = mirror.children.map { child -> String in
            let valueDescription = describing(child.value)
                .debug_updateLinesByShifting()

            switch mirror.displayStyle {
            case .enum:
                if !valueDescription.contains("\n") {
                    return "\(child.label ?? "nil")(\(valueDescription))"
                } else {
                    return "\(child.label ?? "nil")(\n\(valueDescription)\n)"
                }
            case .collection, .set, .tuple:
                return "\(valueDescription)"
            case .dictionary, .none, .class, .struct, .optional:
                return "\(child.label ?? "nil") = \(valueDescription)"
            @unknown default:
                return "\(child.label ?? "nil") = \(valueDescription)"
            }
        }

        let valuesDescription = values.joined(separator: ",\n")

        switch mirror.displayStyle {
        case .enum:
            return "\(title).\(valuesDescription)"
        case .collection, .set, .dictionary:
            let title = title.split(separator: "<")
                .first
                .map { "\($0)" } ?? title
            return "\(title) [\n\(valuesDescription)\n]"
        case .tuple:
            return "Tuple (\n\(valuesDescription)\n)"
        default:
            return "\(title) {\n\(valuesDescription)\n}"
        }
    }
    #endif

    var debugDescription: String {
        #if DEBUG
        return Self.describing(self, root: true)
        #else
        return String(describing: type(of: self))
        #endif
    }
}
