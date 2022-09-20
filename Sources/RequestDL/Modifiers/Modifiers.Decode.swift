import Foundation

extension Modifiers {

    public struct Decode<Content: Task, Element: Decodable>: TaskModifier where Content.Element == TaskResult<Data> {

        let type: Element.Type
        let decoder: JSONDecoder
        private let contentType: DecodeContentType

        fileprivate init(_ type: Element.Type, decoder: JSONDecoder, contentType: DecodeContentType) {
            self.type = type
            self.decoder = decoder
            self.contentType = contentType
        }

        public func task(_ task: Content) async throws -> TaskResult<Element> {
            let result = try await task.response()

            return .init(
                response: result.response,
                data: try decoder.decode(type, from: flatMap(result.data))
            )
        }
    }
}

extension Modifiers.Decode {

    private func flatMap(_ data: Data) -> Data {
        switch contentType {
        case .plain:
            return data
        case .array:
            return data.isEmpty ? "[]".data(using: .utf8) ?? data : data
        case .dictionary:
            return data.isEmpty ? "{}".data(using: .utf8) ?? data : data
        }
    }
}

extension Task where Element == TaskResult<Data> {

    public func decode<T: Decodable>(
        _ type: T.Type,
        decoder: JSONDecoder = .init()
    ) -> ModifiedTask<Modifiers.Decode<Self, T>> {
        modify(Modifiers.Decode(type, decoder: decoder, contentType: .plain))
    }

    public func decode<T: Decodable>(
        _ type: T.Type,
        decoder: JSONDecoder = .init()
    ) -> ModifiedTask<Modifiers.Decode<Self, T>> where T: Collection {
        modify(Modifiers.Decode(type, decoder: decoder, contentType: .array))
    }

    public func decode<Key: Decodable, Value: Decodable>(
        _ type: [Key: Value].Type,
        decoder: JSONDecoder = .init()
    ) -> ModifiedTask<Modifiers.Decode<Self, [Key: Value]>> {
        modify(Modifiers.Decode(type, decoder: decoder, contentType: .dictionary))
    }
}

fileprivate enum DecodeContentType {
    case plain
    case array
    case dictionary
}
