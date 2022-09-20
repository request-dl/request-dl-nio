//
//  Modifiers.OnStatusCode.swift
//  
//
//  Created by onnerb on 12/07/22.
//

import Foundation

extension Modifiers {

    public struct OnStatusCode<Content: Task>: TaskModifier where Content.Element: TaskResultPrimitive {

        private let contains: (Int) -> Bool
        private let mapHandler: (Content.Element) throws -> Void

        init(contains: @escaping (Int) -> Bool, map: @escaping (Content.Element) throws -> Void) {
            self.contains = contains
            self.mapHandler = map
        }

        public func task(_ task: Content) async throws -> Content.Element {
            let result = try await task.response()

            guard
                let response = result.response as? HTTPURLResponse,
                contains(response.statusCode)
            else { return result }

            try mapHandler(result)
            return result
        }
    }
}

extension Task where Element: TaskResultPrimitive {

    private func onStatusCode(
        _ map: @escaping (Element) throws -> Void,
        contains: @escaping (Int) -> Bool
    ) -> ModifiedTask<Modifiers.OnStatusCode<Self>> {
        modify(.init(
            contains: contains,
            map: map
        ))
    }

    public func onStatusCode(
        _ statusCode: Range<Int>,
        _ mapHandler: @escaping (Element) throws -> Void
    ) -> ModifiedTask<Modifiers.OnStatusCode<Self>> {
        onStatusCode(mapHandler) {
            statusCode.contains($0)
        }
    }

    public func onStatusCode(
        _ statusCode: Set<Int>,
        _ mapHandler: @escaping (Element) throws -> Void
    ) -> ModifiedTask<Modifiers.OnStatusCode<Self>> {
        onStatusCode(mapHandler) {
            statusCode.contains($0)
        }
    }

    public func onStatusCode(
        _ statusCode: Int,
        _ mapHandler: @escaping (Element) throws -> Void
    ) -> ModifiedTask<Modifiers.OnStatusCode<Self>> {
        onStatusCode(mapHandler) {
            statusCode == $0
        }
    }
}
